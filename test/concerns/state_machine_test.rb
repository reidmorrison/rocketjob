require_relative '../test_helper'

# Unit Test for RocketJob::Job
class StateMachineTest < Minitest::Test

  class Test
    include RocketJob::Concerns::Document
    include RocketJob::Concerns::StateMachine

    key :name
    key :state
    validates_presence_of :name, :state

    aasm column: :state do
      state :pending, initial: true
      state :enabled

      event :enable do
        transitions from: :pending, to: :enabled
      end
    end
  end

  describe RocketJob::Concerns::Persistence do
    before do
      @doc = Test.new
    end

    after do
      @doc.destroy if @doc && !@doc.new_record?
    end

    describe '#aasm_write_state' do
      it 'raises an exception when a validation fails on create!' do
        assert_raises MongoMapper::DocumentNotValid do
          @doc = Test.create!
        end
      end

      it 'raises an exception when a validation fails on save' do
        assert_raises MongoMapper::DocumentNotValid do
          @doc.save!
        end
      end

      it 'raises an exception when a validation fails on state transition with save' do
        assert_raises MongoMapper::DocumentNotValid do
          @doc.enable!
        end
        assert @doc.pending?
        refute @doc.valid?
      end

      it 'does not raise an exception when a validation fails on state transition without save' do
        @doc.enable
        assert @doc.enabled?
      end

    end

  end
end
