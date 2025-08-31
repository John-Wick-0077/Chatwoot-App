class Integrations::Toqan::ProcessorService < Integrations::BotProcessorService
  pattr_initialize [:event_name!, :hook!, :event_data!]

  def perform
    message = event_data[:message]
    Rails.logger.info "[Toqan] Message ID: #{message.id}, content: #{message.content}"
    result=should_run_processor?(message)
    Rails.logger.info "[Toqan] should_run_processor?: #{result}"
    return unless  result

    agent = message.conversation.assignee || Account.find(message.account_id).users.first
    Rails.logger.info "[Toqan] Using agent: #{agent.id} (#{agent.name}) for typing status"

    begin
      Rails.logger.info('[Toqan] Triggering typing ON')
      ::Conversations::TypingStatusManager.new(message.conversation, agent, typing_params('on')).toggle_typing_status
    rescue StandardError => e
      Rails.logger.error("[Toqan] Typing status toggle failed (ON): #{e.class} - #{e.message}")
    end
    session_id = message.sender_id
    text = message.content
    response = get_response(session_id, text)
    process_action(message, 'handoff') if response.strip.downcase.include?('transferring you to a human agent...')

    begin
      Rails.logger.info('[Toqan] Triggering typing OFF')
      ::Conversations::TypingStatusManager.new(message.conversation, agent, typing_params('off')).toggle_typing_status
    rescue StandardError => e
      Rails.logger.error("[Toqan] Typing status toggle failed (OFF): #{e.class} - #{e.message}")
    end

    return 'Sorry, no answer received' if response.nil? || response.empty?

    Rails.logger.info "[Toqan] → Toqan API raw response: #{response.inspect}"
    create_conversation(message, response)
  end

  def typing_params(status)
    {
      typing_status: status,
      is_private: false
    }.with_indifferent_access
  end

  private

  def toggle_typing_status(status)
    manager = ::Conversations::TypingStatusManager.new(@conversation, @contact, {
                                                         typing_status: status,
                                                         is_private: false
                                                       })
    manager.toggle_typing_status
  rescue StandardError => e
    Rails.logger.error("[Toqan] Typing status toggle failed: #{e.class} - #{e.message}")
  end

  def get_response(_session_id, text)
    # Step 1: Call create_conversation
    return 'Transferring you to a human agent...' if handoff_requested?(text)

    create_uri = URI.parse('https://api.coco.prod.toqan.ai/api/create_conversation')
    create_http = Net::HTTP.new(create_uri.host, create_uri.port)
    create_http.use_ssl = true

    create_request = Net::HTTP::Post.new(create_uri, default_headers)
    create_request.body = {
      user_message: text
    }.to_json

    Rails.logger.info "[Toqan]  Sending create_conversation to Toqan: #{create_request.body}"
    create_response = create_http.request(create_request)
    create_body = create_response.body.force_encoding('UTF-8')
    Rails.logger.info "[Toqan]  create_conversation response: #{create_body}"

    json = JSON.parse(create_body)
    conversation_id = json['conversation_id']
    request_id = json['request_id']

    if conversation_id.blank? || request_id.blank?
      Rails.logger.warn '[Toqan]  Missing conversation_id or request_id'
      return 'Sorry, failed to get response.'
    end

    # Step 2: Poll for get_answer result
    answer_uri = URI.parse('https://api.coco.prod.toqan.ai/api/get_answer')
    answer_http = Net::HTTP.new(answer_uri.host, answer_uri.port)
    answer_http.use_ssl = true

    retries = 0
    max_retries = 10
    poll_interval = 1.5

    loop do
      answer_request = Net::HTTP::Get.new(answer_uri, default_headers)
      answer_request.body = {
        conversation_id: conversation_id,
        request_id: request_id
      }.to_json

      Rails.logger.info "[Toqan]  Sending get_answer request: #{answer_request.body}"
      answer_response = answer_http.request(answer_request)
      answer_body = answer_response.body.force_encoding('UTF-8')
      Rails.logger.info "[Toqan]  get_answer response: #{answer_body}"

      answer_json = JSON.parse(answer_body)
      status = answer_json['status']
      final_answer = answer_json['answer']

      if status == 'finished' && final_answer.present?
        Rails.logger.info "[Toqan]  Final answer: #{final_answer}"
        return final_answer
      end

      retries += 1
      if retries >= max_retries
        Rails.logger.warn '[Toqan]  Max retries reached, aborting.'
        return 'Sorry, response took too long.'
      end

      sleep poll_interval
    end

  rescue StandardError => e
    Rails.logger.error("[Toqan]  Error during Toqan API call: #{e.class} - #{e.message}")
    'Something went wrong.'
  end

  def handoff_requested?(text)
    text.downcase.match?(/(transfer|talk|speak).*(human|agent)/)
  end

  def default_headers
    {
      'Content-Type' => 'application/json',
      'Accept' => '*/*',
      'X-Api-Key' => hook.settings['api_key']
    }
  end

  def create_conversation(message, content)
    message.conversation.messages.create!(
      content: content,
      message_type: :outgoing,
      account_id: message.account_id,
      inbox_id: message.inbox_id
    )
  end
end
