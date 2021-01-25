require "optparse"
require "csv"
require "yaml"
module RocketJob
  module Batch
    class Performance
      attr_accessor :count, :servers, :workers, :version, :ruby, :environment, :mongo_config, :compress, :encrypt, :slice_size

      def initialize
        @count        = 10_000_000
        @environment  = ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development"
        @mongo_config = "config/mongoid.yml"
        @compress     = false
        @encrypt      = false
        @slice_size   = 1000
      end

      def run_test_case(count = self.count)
        servers = RocketJob::Server.count
        raise "Please start workers before starting the performance test" if servers.zero?

        count_running_workers

        puts "Loading job with #{count} records/lines"
        args = {log_level: :warn, slice_size: slice_size}
        if defined?(::RocketJob)
          args[:compress] = compress
          args[:encrypt]  = encrypt
        end
        job = RocketJob::Jobs::PerformanceJob.new(args)
        job.upload do |writer|
          count.times { |i| writer << i }
        end
        job.save!

        puts "Waiting for job to complete"
        sleep 3 until job.reload.completed?

        duration = job.completed_at - job.started_at
        {
          count:              count,
          duration:           duration,
          records_per_second: (count.to_f / duration).round(3),
          workers:            workers,
          servers:            servers,
          compress:           compress,
          encrypt:            encrypt
        }
      end

      # Export the Results hash to a CSV file
      def export_results(results)
        ruby    = defined?(JRuby) ? "jruby_#{JRUBY_VERSION}" : "ruby_#{RUBY_VERSION}"
        version = RocketJob::VERSION

        CSV.open("job_results_#{ruby}_v#{version}.csv", "wb") do |csv|
          csv << results.first.keys
          results.each { |result| csv << result.values }
        end
      end

      # Parse command line options
      def parse(argv)
        parser = OptionParser.new do |o|
          o.on("-c", "--count COUNT", "Count of records to enqueue") do |arg|
            self.count = arg.to_i
          end
          o.on("-m", "--mongo MONGO_CONFIG_FILE_NAME", "Location of mongoid.yml config file") do |arg|
            self.mongo_config = arg
          end
          o.on("-e", "--environment ENVIRONMENT",
               "The environment to run the app on (Default: RAILS_ENV || RACK_ENV || development)") do |arg|
            self.environment = arg
          end
          o.on("-z", "--compress", "Turn on compression") do
            self.compress = true
          end
          o.on("-E", "--encrypt", "Turn on encryption") do
            self.encrypt = true
          end
          o.on("-s", "--slice_size COUNT", "Slice size") do
            self.slice_size = arg.to_i
          end
        end
        parser.banner = "rocketjob_batch_perf <options>"
        parser.on_tail "-h", "--help", "Show help" do
          puts parser
          exit 1
        end
        parser.parse! argv
      end

      def count_running_workers
        self.servers = 0
        self.workers = 0
        RocketJob::Server.running.each do |server|
          next if server.zombie?

          self.servers += 1
          self.workers += server.heartbeat.workers
        end
        puts "Running: #{workers} workers, distributed across #{servers} servers"
      end
    end
  end
end
