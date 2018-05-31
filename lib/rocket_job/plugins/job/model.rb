require 'active_support/concern'

module RocketJob
  module Plugins
    module Job
      # Prevent more than one instance of this job class from running at a time
      module Model
        extend ActiveSupport::Concern

        included do
          # Fields that are end user editable.
          # For example are editable in Rocket Job Web Interface.
          class_attribute :user_editable_fields, instance_accessor: false
          self.user_editable_fields = []

          # Attributes to include when copying across the attributes to a new instance on restart.
          class_attribute :rocket_job_restart_attributes
          self.rocket_job_restart_attributes = []

          #
          # User definable attributes
          #
          # The following attributes are set when the job is created

          # Description for this job instance
          field :description, type: String, class_attribute: true, user_editable: true, copy_on_restart: true

          # Priority of this job as it relates to other jobs [1..100]
          #   1: Highest Priority
          #  50: Default Priority
          # 100: Lowest Priority
          #
          # Example:
          #   A job with a priority of 40 will execute before a job with priority 50
          #
          # In RocketJob Pro, if a SlicedJob is running and a higher priority job
          # arrives, then the current job will complete the current slices and process
          # the new higher priority job
          field :priority, type: Integer, default: 50, class_attribute: true, user_editable: true, copy_on_restart: true

          # When the job completes destroy it from both the database and the UI
          field :destroy_on_complete, type: Boolean, default: true, class_attribute: true, copy_on_restart: true

          # Whether to store the results from this job
          field :collect_output, type: Boolean, default: false, class_attribute: true

          # Run this job no earlier than this time
          field :run_at, type: Time, user_editable: true

          # If a job has not started by this time, destroy it
          field :expires_at, type: Time, copy_on_restart: true

          # Raise or lower the log level when calling the job
          # Can be used to reduce log noise, especially during high volume calls
          # For debugging a single job can be logged at a low level such as :trace
          #   Levels supported: :trace, :debug, :info, :warn, :error, :fatal
          field :log_level, type: Symbol, class_attribute: true, user_editable: true, copy_on_restart: true

          #
          # Read-only attributes
          #

          # Current state, as set by the state machine. Do not modify this value directly.
          field :state, type: Symbol, default: :queued

          # When the job was created
          field :created_at, type: Time, default: -> { Time.now }

          # When processing started on this job
          field :started_at, type: Time

          # When the job completed processing
          field :completed_at, type: Time

          # Number of times that this job has failed to process
          field :failure_count, type: Integer, default: 0

          # This name of the worker that this job is being processed by, or was processed by
          field :worker_name, type: String

          #
          # Values that jobs can update during processing
          #

          # Allow a job to updates its estimated progress
          # Any integer from 0 to 100
          field :percent_complete, type: Integer, default: 0

          # Store the last exception for this job
          embeds_one :exception, class_name: 'RocketJob::JobException'

          # Store the Hash result from this job if collect_output is true,
          # and the job returned actually returned a Hash, otherwise nil
          # Not applicable to SlicedJob jobs, since its output is stored in a
          # separate collection
          field :result, type: Hash

          index({state: 1, priority: 1, _id: 1}, background: true)

          validates_presence_of :state, :failure_count, :created_at
          validates :priority, inclusion: 1..100
          validates :log_level, inclusion: SemanticLogger::LEVELS + [nil]
        end

        module ClassMethods
          # Returns [String] the singular name for this job class
          #
          # Example:
          #   job = DataStudyJob.new
          #   job.underscore_name
          #   # => "data_study"
          def underscore_name
            @underscore_name ||= name.sub(/Job$/, '').underscore
          end

          # Allow the collective name for this job class to be overridden
          def underscore_name=(underscore_name)
            @underscore_name = underscore_name
          end

          # Returns [String] the human readable name for this job class
          #
          # Example:
          #   job = DataStudyJob.new
          #   job.human_name
          #   # => "Data Study"
          def human_name
            @human_name ||= name.sub(/Job$/, '').titleize
          end

          # Allow the human readable job name for this job class to be overridden
          def human_name=(human_name)
            @human_name = human_name
          end

          # Returns [String] the collective name for this job class
          #
          # Example:
          #   job = DataStudyJob.new
          #   job.collective_name
          #   # => "data_studies"
          def collective_name
            @collective_name ||= name.sub(/Job$/, '').pluralize.underscore
          end

          # Allow the collective name for this job class to be overridden
          def collective_name=(collective_name)
            @collective_name = collective_name
          end

          # Scope for jobs scheduled to run in the future
          def scheduled
            queued.where(:run_at.gt => Time.now)
          end

          # Scope for queued jobs that can run now
          # I.e. Queued jobs excluding scheduled jobs
          def queued_now
            queued.or({run_at: nil}, :run_at.lte => Time.now)
          end

          # Defines all the fields that are accessible on the Document
          # For each field that is defined, a getter and setter will be
          # added as an instance method to the Document.
          #
          # @example Define a field.
          #   field :score, :type => Integer, :default => 0
          #
          # @param [ Symbol ] name The name of the field.
          # @param [ Hash ] options The options to pass to the field.
          #
          # @option options [ Class ] :type The type of the field.
          # @option options [ String ] :label The label for the field.
          # @option options [ Object, Proc ] :default The field's default
          # @option options [ Boolean ] :class_attribute Keep the fields default in a class_attribute
          # @option options [ Boolean ] :user_editable Field can be edited by end users in RJMC
          #
          # @return [ Field ] The generated field
          def field(name, options)
            if options.delete(:user_editable) == true
              self.user_editable_fields += [name.to_sym] unless user_editable_fields.include?(name.to_sym)
            end
            if options.delete(:class_attribute) == true
              class_attribute(name, instance_accessor: false)
              public_send("#{name}=", options[:default]) if options.key?(:default)
              options[:default] = -> { self.class.public_send(name) }
            end
            if options.delete(:copy_on_restart) == true
              self.rocket_job_restart_attributes += [name.to_sym] unless rocket_job_restart_attributes.include?(name.to_sym)
            end
            super(name, options)
          end

          # DEPRECATED
          def rocket_job
            warn 'Replace calls to .rocket_job with calls to set class instance variables. For example: self.priority = 50'
            yield(self)
          end

          # DEPRECATED
          def public_rocket_job_properties(*args)
            warn "Replace calls to .public_rocket_job_properties by adding `user_editable: true` option to the field declaration in #{name} for: #{args.inspect}"
            self.user_editable_fields += args.collect(&:to_sym)
          end
        end

        # Returns [true|false] whether to collect nil results from running this batch
        def collect_nil_output?
          collect_output? ? (collect_nil_output == true) : false
        end

        # Returns [true|false] whether to collect the results from running this batch
        def collect_output?
          collect_output == true
        end

        # Returns [Float] the number of seconds the job has taken
        # - Elapsed seconds to process the job from when a worker first started working on it
        #   until now if still running, or until it was completed
        # - Seconds in the queue if queued
        def seconds
          if completed_at
            completed_at - (started_at || created_at)
          elsif started_at
            Time.now - started_at
          else
            Time.now - created_at
          end
        end

        # Returns a human readable duration the job has taken
        def duration
          RocketJob.seconds_as_duration(seconds)
        end

        # Returns [true|false] whether the job has expired
        def expired?
          expires_at && (expires_at < Time.now)
        end

        # Returns [true|false] whether the job is scheduled to run in the future
        def scheduled?
          queued? && run_at.present? && (run_at > Time.now)
        end

        # Return [true|false] whether this job is sleeping.
        # I.e. No workers currently working on this job even if it is running.
        def sleeping?
          running? && worker_count.zero?
        end

        # Returns [Integer] the number of workers currently working on this job.
        def worker_count
          running? && worker_name.present? ? 1 : 0
        end

        # Returns [Array<String>] names of workers currently working this job.
        def worker_names
          running? && worker_name.present? ? [worker_name] : []
        end

        # Clear `run_at` so that this job will run now.
        def run_now!
          update_attributes(run_at: nil) if run_at
        end

        # Returns [Time] at which this job was intended to run at.
        #
        # Takes into account any delays that could occur.
        # Recommended to use this Time instead of Time.now in the `#perform` since the job could run outside its
        # intended window. Especially if a failed job is only retried quite sometime later.
        def scheduled_at
          run_at || created_at
        end

        # Returns [Hash] status of this job
        def as_json
          attrs = serializable_hash(methods: %i[seconds duration])
          attrs.delete('result') unless collect_output?
          attrs.delete('failure_count') unless failure_count.positive?
          if queued?
            attrs.delete('started_at')
            attrs.delete('completed_at')
            attrs.delete('result')
            attrs
          elsif running?
            attrs.delete('completed_at')
            attrs.delete('result')
            attrs
          elsif completed?
            attrs.delete('percent_complete')
            attrs
          elsif paused?
            attrs.delete('completed_at')
            attrs.delete('result')
            # Ensure 'paused_at' appears first in the hash
            {'paused_at' => completed_at}.merge(attrs)
          elsif aborted?
            attrs.delete('completed_at')
            attrs.delete('result')
            {'aborted_at' => completed_at}.merge(attrs)
          elsif failed?
            attrs.delete('completed_at')
            attrs.delete('result')
            {'failed_at' => completed_at}.merge(attrs)
          else
            attrs
          end
        end

        # Returns [Hash] the status of this job
        def status(time_zone = 'Eastern Time (US & Canada)')
          h = as_json
          h.delete('seconds')
          h.dup.each_pair do |k, v|
            if v.is_a?(Time)
              h[k] = v.in_time_zone(time_zone).to_s
            elsif v.is_a?(BSON::ObjectId)
              h[k] = v.to_s
            end
          end
          h
        end

        # Returns [Boolean] whether the worker runs on a particular server.
        def worker_on_server?(server_name)
          return false unless worker_name.present? && server_name.present?
          worker_name.start_with?(server_name)
        end
      end
    end
  end
end
