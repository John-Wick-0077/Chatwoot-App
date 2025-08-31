# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

module Integrations
  module Openai
    class ProcessorService < Integrations::OpenaiBaseService
      attr_reader :hook, :event

      def initialize(hook:, event:)
        @hook = hook
        @event = event
      end

      TOQAN_API_KEY  = ENV.fetch('TOQAN_API_KEY') do
        raise 'ENV["TOQAN_API_KEY"] is not set'
      end
      API_BASE_URL   = 'https://api.coco.prod.toqan.ai/api'
      POLL_DELAY_SEC = 1.5
      MAX_POLLS      = 10

      AGENT_INSTRUCTION    = 'You are a helpful support agent.'
      LANGUAGE_INSTRUCTION = 'Ensure that the reply should be in user language.'

      def reply_suggestion_message
        system_prompt = prompt_from_file('reply')
        user_prompt   = conversation_messages
        result        = call_toqan("#{system_prompt}\n\n#{user_prompt}")
        { message: result[:data][:message] }
      end

      def summarize_message
        system_prompt = prompt_from_file('summary')
        user_prompt   = conversation_messages
        result        = call_toqan("#{system_prompt}\n\n#{user_prompt}")
        { message: result[:data][:message] }
      end

      def rephrase_message
        prompt = "#{AGENT_INSTRUCTION} Please rephrase the following response. " \
                 "#{LANGUAGE_INSTRUCTION}\n\n#{event['data']['content']}"
        result = call_toqan(prompt)
        { message: result[:data][:message] }
      end

      def fix_spelling_grammar_message
        prompt = <<~PROMPT
          #{AGENT_INSTRUCTION}
          Fix the spelling and grammar of the text below. Assume the user meant something meaningful, even if unclear.
          Respond only with the corrected version — no explanations, no notes, just the corrected sentence.
          Use sentence case and proper punctuation.

          "#{event['data']['content']}"
        PROMPT
        result = call_toqan(prompt)
        { message: result[:data][:message] }
      end

      def shorten_message
        prompt = "#{AGENT_INSTRUCTION} Please shorten the following response. " \
                 "#{LANGUAGE_INSTRUCTION}\n\n#{event['data']['content']}"
        result = call_toqan(prompt)
        { message: result[:data][:message] }
      end

      def expand_message
        prompt = "#{AGENT_INSTRUCTION} Please expand the following response. " \
                 "#{LANGUAGE_INSTRUCTION}\n\n#{event['data']['content']}"
        result = call_toqan(prompt)
        { message: result[:data][:message] }
      end

      def make_friendly_message
        prompt = "#{AGENT_INSTRUCTION} Please make the following response more friendly. " \
                 "#{LANGUAGE_INSTRUCTION}\n\n#{event['data']['content']}"
        result = call_toqan(prompt)
        { message: result[:data][:message] }
      end

      def make_formal_message
        prompt = "#{AGENT_INSTRUCTION} Please make the following response more formal. " \
                 "#{LANGUAGE_INSTRUCTION}\n\n#{event['data']['content']}"
        result = call_toqan(prompt)
        { message: result[:data][:message] }
      end

      def simplify_message
        prompt = "#{AGENT_INSTRUCTION} Please simplify the following response. " \
                 "#{LANGUAGE_INSTRUCTION}\n\n#{event['data']['content']}"
        result = call_toqan(prompt)
        { message: result[:data][:message] }
      end

      def call_toqan(user_message)
        Rails.logger.info("[Toqan] ► create_conversation\n#{user_message}")

        conv_id, req_id = create_conversation(user_message)
        return openai_like_response('Failed to start conversation') unless conv_id && req_id

        raw_answer = nil
        MAX_POLLS.times do |i|
          sleep POLL_DELAY_SEC
          raw_answer = fetch_answer(conv_id, req_id)
          break if raw_answer.present?

          Rails.logger.debug { "[Toqan] answer not ready (poll #{i + 1})" }
        end
        final_answer = if raw_answer.is_a?(Hash)
                         raw_answer[:answer] || raw_answer['answer']
                       else
                         raw_answer
                       end
        final_answer ||= 'No answer received from Toqan'
        openai_like_response(clean_answer(final_answer))

      rescue StandardError => e
        Rails.logger.error("[Toqan] #{e.class}: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        openai_like_response('Error contacting Toqan')
      end

      def openai_like_response(content)
        {
          data: {
            message: content
          }
        }
      end

      def clean_answer(raw)
        return '' unless raw

        CGI.unescapeHTML(raw)
           .gsub(%r{<think>.*?</think>}m, '')
           .strip
      end

      def log_request(method, uri, body)
        Rails.logger.debug { "[Toqan] Request: #{method} #{uri} - Body: #{body.truncate(200)}" }
      end

      def create_conversation(message)
        uri  = URI("#{API_BASE_URL}/create_conversation")
        body = { user_message: message }.to_json
        log_request('POSTarihant', uri, body)
        res  = Net::HTTP.post(uri, body, headers)

        log_http('create_conversation', res)
        return unless res.is_a?(Net::HTTPSuccess)

        json = safe_parse(res.body)
        [json['conversation_id'], json['request_id']]
      end

      def fetch_answer(conversation_id, request_id)
        uri = URI("#{API_BASE_URL}/get_answer")
        http     = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        request  = Net::HTTP::Get.new(uri.request_uri, headers)
        request.body = { conversation_id: conversation_id,
                         request_id: request_id }.to_json

        log_request('getanrihant', uri, request.body)
        res = http.request(request)
        log_http('get_answer', res)
        return unless res.is_a?(Net::HTTPSuccess)

        json = safe_parse(res.body)
        json['answer']
      end

      def headers
        {
          'X-Api-Key' => TOQAN_API_KEY,
          'Content-Type' => 'application/json',
          'Accept' => '*/*'
        }
      end

      def safe_parse(str)
        JSON.parse(str)
      rescue JSON::ParserError
        Rails.logger.error("[Toqan] JSON parse error for body: #{str.inspect}")
        {}
      end

      def log_http(step, res)
        log_data = {
          step: step,
          status: res.code,
          headers: res.each_header.to_h,
          body: safe_parse(res.body),
          raw_body: res.body.truncate(400)
        }

        Rails.logger.info("[Toqan] Response details: #{log_data.to_json}")
      rescue StandardError => e
        Rails.logger.error("[Toqan] Error logging response: #{e.message}")
      end

      def prompt_from_file(name, enterprise: false)
        path = if enterprise
                 'enterprise/lib/enterprise/integrations/openai_prompts'
               else
                 'lib/integrations/openai/openai_prompts'
               end
        Rails.root.join(path, "#{name}.txt").read
      end
    end
  end
end
