require_relative "../test_helper"

module Plugins
  class StateMachineTest < Minitest::Test
    class Test
      include RocketJob::Plugins::Document
      include RocketJob::Plugins::StateMachine

      field :name, type: String
      field :state, type: String
      validates_presence_of :name, :state

      aasm column: :state, whiny_persistence: true do
        state :pending, initial: true
        state :enabled

        event :enable do
          transitions from: :pending, to: :enabled
        end
      end
    end

    describe RocketJob::Plugins::StateMachine do
      before { Test.delete_all }
      let(:job) { Test.new }

      describe "#create!" do
        it "raises an exception when a validation fails on create!" do
          assert_raises ::Mongoid::Errors::Validations do
            Test.create!
          end
        end
      end

      describe "#save!" do
        it "raises an exception when a validation fails on save" do
          assert_raises ::Mongoid::Errors::Validations do
            job.save!
          end
        end
      end

      describe "#transition!" do
        it "raises an exception when a validation fails on state transition with save" do
          assert_raises ::Mongoid::Errors::Validations do
            job.enable!
          end
          assert job.pending?
          refute job.valid?
        end
      end

      describe "#transition" do
        it "does not raise an exception when a validation fails on state transition without save" do
          job.enable
          assert job.enabled?
        end
      end
    end
  end
end
