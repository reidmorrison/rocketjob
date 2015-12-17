module RocketJob
  module Jobs

    class SimpleJob < RocketJob::Job
      # No operation, used for performance testing
      def perform
      end
    end

  end
end
