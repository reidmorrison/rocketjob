require_relative '../test_helper'

module Plugins
  # Unit Test for RocketJob::Job
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
      before do
        @doc = Test.new
      end

      after do
        @doc.destroy if @doc && !@doc.new_record?
      end

      describe '#create!' do
        it 'raises an exception when a validation fails on create!' do
          assert_raises Mongoid::Errors::Validations do
            @doc = Test.create!
          end
        end
      end

      describe '#save!' do
        it 'raises an exception when a validation fails on save' do
          assert_raises Mongoid::Errors::Validations do
            @doc.save!
          end
        end
      end

      describe '#transition!' do
        it 'raises an exception when a validation fails on state transition with save' do
          assert_raises Mongoid::Errors::Validations do
            @doc.enable!
          end
          assert @doc.pending?
          refute @doc.valid?
        end
      end

      describe '#transition' do
        it 'does not raise an exception when a validation fails on state transition without save' do
          @doc.enable
          assert @doc.enabled?
        end
      end
    end
  end
end
