require_relative '../test_helper'
require 'active_record'

ActiveRecord::Base.configurations = YAML.safe_load(ERB.new(IO.read('test/config/database.yml')).result)
ActiveRecord::Base.establish_connection(:test)

ActiveRecord::Schema.define version: 0 do
  create_table :users, force: true do |t|
    t.string :login
  end
end

class User < ActiveRecord::Base
end

module Plugins
  class TransactionTest < Minitest::Test
    class CommitTransactionJob < RocketJob::Job
      # Wrap perform with a transaction, so that it is rolled back on exception.
      include RocketJob::Plugins::Transaction

      field :login, type: String

      def perform
        User.create!(login: login)
      end
    end

    class RollbackTransactionJob < RocketJob::Job
      # Wrap perform with a transaction, so that it is rolled back on exception.
      include RocketJob::Plugins::Transaction

      field :login, type: String

      def perform
        User.create!(login: login)
        raise 'This must fail and rollback the transaction'
      end
    end

    describe RocketJob::Plugins::Job::Logger do
      before do
        User.delete_all
        CommitTransactionJob.delete_all
        RollbackTransactionJob.delete_all
      end

      after do
        @job.destroy if @job && !@job.new_record?
      end

      describe '#rocket_job_transaction' do
        it 'is registered' do
          assert(CommitTransactionJob.send(:get_callbacks, :perform).find { |c| c.filter == :rocket_job_transaction })
          assert(RollbackTransactionJob.send(:get_callbacks, :perform).find { |c| c.filter == :rocket_job_transaction })
          refute(RocketJob::Job.send(:get_callbacks, :perform).find { |c| c.filter == :rocket_job_transaction })
        end
      end

      describe '#perform' do
        it 'commits on success' do
          assert_equal 0, User.count
          job = CommitTransactionJob.new(login: 'Success')
          job.perform_now
          assert job.completed?
          assert_equal 1, User.count
          assert_equal 'Success', User.first.login
        end

        it 'rolls back on exception' do
          assert_equal 0, User.count
          job = RollbackTransactionJob.new(login: 'Bad')
          assert_raises RuntimeError do
            job.perform_now
          end
          assert job.failed?
          assert_equal 0, User.count
        end
      end
    end
  end
end
