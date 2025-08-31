Rails.application.config.after_initialize do
  if ENV['DISABLE_TELEMETRY'] == 'true'
    Rails.logger.info '[Telemetry] DISABLED — monkey patching ChatwootHub methods.'

    module ChatwootHubPatch
      def emit_event(*)
        Rails.logger.info '[Telemetry] emit_event skipped due to DISABLE_TELEMETRY'
        nil
      end

      def sync_with_hub
        Rails.logger.info '[Telemetry] sync_with_hub skipped due to DISABLE_TELEMETRY'
        nil
      end
    end

    ChatwootHub.singleton_class.prepend(ChatwootHubPatch)
  end
end
