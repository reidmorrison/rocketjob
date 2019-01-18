require 'yaml'
require 'active_support/concern'

module RocketJob
  class Server
    # Model attributes
    module Model
      extend ActiveSupport::Concern

      included do
        store_in collection: 'rocket_job.servers'

        # Unique Name of this server instance
        #   Default: `host name:PID`
        # The unique name is used on re-start to re-queue any jobs that were being processed
        # at the time the server unexpectedly terminated, if any
        field :name, type: String, default: -> { "#{SemanticLogger.host}:#{$$}" }

        # The maximum number of workers this server should start
        #   If set, it will override the default value in RocketJob::Config
        field :max_workers, type: Integer, default: -> { Config.instance.max_workers }

        # When this server process was started
        field :started_at, type: Time

        # Filter to apply to control which job classes this server can process
        field :yaml_filter, type: String

        # The heartbeat information for this server
        embeds_one :heartbeat, class_name: 'RocketJob::Heartbeat'

        # Current state
        #   Internal use only. Do not set this field directly
        field :state, type: Symbol, default: :starting

        index({name: 1}, background: true, unique: true, drop_dups: true)

        validates_presence_of :state, :name, :max_workers

        # Requeue any jobs being worked by this server when it is destroyed
        before_destroy :requeue_jobs

        # Returns [Hash<String:Integer>] of the number of servers in each state.
        # Note: If there are no servers in that particular state then the hash will not have a value for it.
        #
        # Example servers in every state:
        #   RocketJob::Server.counts_by_state
        #   # => {
        #          :aborted => 1,
        #          :completed => 37,
        #          :failed => 1,
        #          :paused => 3,
        #          :queued => 4,
        #          :running => 1,
        #          :queued_now => 1,
        #          :scheduled => 3
        #        }
        #
        # Example no servers active:
        #   RocketJob::Server.counts_by_state
        #   # => {}
        def self.counts_by_state
          counts = {}
          collection.aggregate([{'$group' => {_id: '$state', count: {'$sum' => 1}}}]).each do |result|
            counts[result['_id'].to_sym] = result['count']
          end
          counts
        end

        # Destroy's all instances of zombie servers and requeues any jobs still "running"
        # on those servers.
        def self.destroy_zombies
          count = 0
          each do |server|
            next unless server.zombie?
            logger.warn "Destroying zombie server #{server.name}, and requeueing its jobs"
            server.destroy
            count += 1
          end
          count
        end

        # Scope for all zombie servers
        def self.zombies(missed = 4)
          dead_seconds        = Config.instance.heartbeat_seconds * missed
          last_heartbeat_time = Time.now - dead_seconds
          where(
            :state.in => %i[stopping running paused],
            '$or'     => [
              {'heartbeat.updated_at' => {'$exists' => false}},
              {'heartbeat.updated_at' => {'$lte' => last_heartbeat_time}}
            ]
          )
        end

      end

      # Where clause filter to apply to workers looking for jobs
      def filter
        YAML.load(yaml_filter) if yaml_filter
      end

      def filter=(hash)
        self.yaml_filter = hash.nil? ? nil : hash.to_yaml
      end

      # Returns [true|false] if this server has missed at least the last 4 heartbeats
      #
      # Possible causes for a server to miss its heartbeats:
      # - The server process has died
      # - The server process is "hanging"
      # - The server is no longer able to communicate with the MongoDB Server
      def zombie?(missed = 4)
        return false unless running? || stopping? || paused?
        return true if heartbeat.nil? || heartbeat.updated_at.nil?
        dead_seconds = Config.instance.heartbeat_seconds * missed
        (Time.now - heartbeat.updated_at) >= dead_seconds
      end

      private

      # Requeue any jobs assigned to this server when it is destroyed
      def requeue_jobs
        RocketJob::Job.requeue_dead_server(name)
      end

    end
  end
end
