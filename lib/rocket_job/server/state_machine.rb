require 'active_support/concern'

module RocketJob
  class Server
    # State machine for sliced jobs
    module StateMachine
      extend ActiveSupport::Concern

      included do
        # States
        #   :starting -> :running -> :paused
        #                         -> :stopping
        aasm column: :state, whiny_persistence: true do
          state :starting, initial: true
          state :running
          state :paused
          state :stopping

          event :started do
            transitions from: :starting, to: :running
            before do
              self.started_at = Time.now
            end
          end

          event :pause do
            transitions from: :running, to: :paused
          end

          event :resume do
            transitions from: :paused, to: :running
          end

          event :stop do
            transitions from: :running, to: :stopping
            transitions from: :paused, to: :stopping
            transitions from: :starting, to: :stopping
          end
        end

        # Stop all running, paused, or starting servers
        def self.stop_all
          where(:state.in => %i[running paused starting]).each(&:stop!)
        end

        # Pause all running servers
        def self.pause_all
          running.each(&:pause!)
        end

        # Resume all paused servers
        def self.resume_all
          paused.each(&:resume!)
        end
      end

    end
  end
end
