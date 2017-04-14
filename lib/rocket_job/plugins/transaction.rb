require 'active_support/concern'

module RocketJob
  module Plugins
    # Perform under a single Active Record transaction / unit or work.
    #
    # If the perform raises an exception it will cause any database changes to be rolled back.
    #
    # For Batch Jobs the transaction is at the slice level so that the entire slice succeeds,
    # or is rolled back.
    #
    # Example:
    #   # Update User and create an Audit entry as a single database transaction.
    #   # If Audit.create! fails then the user change will also be rolled back.
    #   class MyJob < RocketJob::Job
    #     include RocketJob::Plugins::Transaction
    #
    #     def perform
    #       u = User.find(name: 'Jack')
    #       u.age = 21
    #       u.save!
    #
    #       Audit.create!(table: 'user', description: 'Changed age to 21')
    #     end
    #   end
    module Transaction
      extend ActiveSupport::Concern

      included do
        if respond_to?(:around_slice)
          around_slice :rocket_job_transaction
        else
          around_perform :rocket_job_transaction
        end
      end

      private

      def rocket_job_transaction(&block)
        ActiveRecord::Base.transaction(&block)
      end
    end
  end
end
