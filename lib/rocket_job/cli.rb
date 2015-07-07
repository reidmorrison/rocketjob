require 'optparse'
module RocketJob
  # Command Line Interface parser for RocketJob
  class CLI
    attr_reader :name, :threads, :environment, :pidfile, :directory, :quiet

    def initialize(argv)
      @name             = nil
      @threads          = nil

      @quiet            = false
      @environment      = ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'
      @pidfile          = nil
      @directory        = '.'
      parse(argv)
    end

    # Run a RocketJob::Server from the command line
    def run
      SemanticLogger.add_appender(STDOUT,  &SemanticLogger::Appender::Base.colorized_formatter) unless quiet
      boot_rails
      write_pidfile

      opts = {}
      opts[:name]             = name if name
      opts[:max_threads]      = threads if threads
      Server.run(opts)
    end

    # Initialize the Rails environment
    def boot_rails
      require File.expand_path("#{directory}/config/environment.rb")
      if Rails.configuration.eager_load
        RocketJob::Server.logger.benchmark_info('Eager loaded Rails and all Engines') do
          Rails.application.eager_load!
          Rails::Engine.subclasses.each { |engine| engine.eager_load! }
        end
      end
    end

    # Create a PID file if requested
    def write_pidfile
      return unless pidfile
      pid = $$
      File.open(pidfile, 'w') { |f| f.puts(pid) }

      # Remove pidfile on exit
      at_exit do
        File.delete(pidfile) if pid == $$
      end
    end

    # Parse command line options placing results in the corresponding instance variables
    def parse(argv)
      parser = OptionParser.new do |o|
        o.on('-n', '--name NAME', 'Unique Name of this server instance (Default: hostname:PID)') { |arg| @name = arg }
        o.on('-t', '--threads COUNT', 'Number of worker threads to start') { |arg| @threads = arg.to_i }
        o.on('-q', '--quiet', 'Do not write to stdout, only to logfile. Necessary when running as a daemon') { @quiet = true }
        o.on('-d', '--dir DIR', 'Directory containing Rails app, if not current directory') { |arg| @directory = arg }
        o.on('-e', '--environment ENVIRONMENT', 'The environment to run the app on (Default: RAILS_ENV || RACK_ENV || development)') { |arg| @environment = arg }
        o.on('--pidfile PATH', 'Use PATH as a pidfile') { |arg| @pidfile = arg }
        o.on('-v', '--version', 'Print the version information') do
          puts "Rocket Job v#{RocketJob::VERSION}"
          exit 1
        end
      end
      parser.banner = 'rocket_job <options>'
      parser.on_tail '-h', '--help', 'Show help' do
        puts parser
        exit 1
      end
      parser.parse! argv
    end

  end
end
