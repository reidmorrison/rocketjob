require 'csv'
require 'yaml'
module RocketJob
  class Performance
    attr_accessor :count, :servers, :workers, :version, :ruby, :environment, :mongo_config

    def initialize
      @version      = RocketJob::VERSION
      @ruby         = defined?(JRuby) ? "jruby_#{JRUBY_VERSION}" : "ruby_#{RUBY_VERSION}"
      @count        = 100_000
      @servers      = 0
      @workers      = 0
      @environment  = ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'
      @mongo_config = 'config/mongo.yml'
    end

    def run_test_case(count = self.count)
      raise 'Please start servers before starting the performance test' if RocketJob::Server.running.count == 0

      self.servers = 0
      self.workers = 0
      RocketJob::Server.running.each do |server|
        unless server.zombie?
          self.servers += 1
          self.workers += server.heartbeat.workers
        end
      end
      puts "Running: #{workers} workers, distributed across #{servers} servers"

      puts 'Waiting for workers to pause'
      RocketJob::Server.pause_all
      RocketJob::Jobs::SimpleJob.delete_all
      sleep 15

      puts 'Enqueuing jobs'
      first = RocketJob::Jobs::SimpleJob.create!(priority: 1, destroy_on_complete: false)
      (count - 2).times { |i| RocketJob::Jobs::SimpleJob.create! }
      last = RocketJob::Jobs::SimpleJob.create!(priority: 100, destroy_on_complete: false)

      puts 'Resuming workers'
      RocketJob::Server.resume_all

      while (!last.reload.completed?)
        sleep 3
      end

      duration = last.reload.completed_at - first.reload.started_at
      {count: count, duration: duration, jobs_per_second: (count.to_f / duration).to_i}
    end

    # Export the Results hash to a CSV file
    def export_results(results)
      CSV.open("job_results_#{ruby}_#{servers}s_#{workers}w_v#{version}.csv", 'wb') do |csv|
        csv << results.first.keys
        results.each { |result| csv << result.values }
      end
    end

    # Parse command line options
    def parse(argv)
      parser        = OptionParser.new do |o|
        o.on('-c', '--count COUNT', 'Count of jobs to enqueue') do |arg|
          self.count = arg.to_i
        end
        o.on('-m', '--mongo MONGO_CONFIG_FILE_NAME', 'Path and filename of config file. Default: config/mongoid.yml') do |arg|
          self.mongo_config = arg
        end
        o.on('-e', '--environment ENVIRONMENT', 'The environment to run the app on (Default: RAILS_ENV || RACK_ENV || development)') do |arg|
          self.environment = arg
        end
      end
      parser.banner = 'rocketjob_perf <options>'
      parser.on_tail '-h', '--help', 'Show help' do
        puts parser
        exit 1
      end
      parser.parse! argv
    end

  end
end
