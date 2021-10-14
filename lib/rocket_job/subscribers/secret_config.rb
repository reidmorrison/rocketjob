module RocketJob
  module Subscribers
    # Cause all instances to refresh their in-memory copy
    # of the Secret Config Registry
    #
    #   RocketJob::Subscribers::SecretConfig.publish(:refresh)
    class SecretConfig
      include RocketJob::Subscriber

      def refresh
        logger.measure_info "Refreshed Secret Config" do
          ::SecretConfig.refresh!
        end
      end
    end
  end
end
