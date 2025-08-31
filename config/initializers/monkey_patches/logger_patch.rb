# config/initializers/restore_logger_broadcast.rb

# Restore Logger.broadcast for Sidekiq 6.5.x compatibility
module ActiveSupport
  class Logger
    def self.broadcast(logger)
      # Return a module that extends the logger with broadcast functionality
      Module.new do
        define_method :add do |severity, message = nil, progname = nil, &block|
          logger.add(severity, message, progname, &block)
          super(severity, message, progname, &block)
        end

        %w[debug info warn error fatal].each do |level|
          define_method level do |*args, &block|
            logger.public_send(level, *args, &block)
            super(*args, &block)
          end
        end
      end
    end
  end
end
