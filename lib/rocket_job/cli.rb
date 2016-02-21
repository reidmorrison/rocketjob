require 'optparse'
require 'yaml'
require 'semantic_logger'
module RocketJob
  # Command Line Interface parser for RocketJob
  class CLI
    include SemanticLogger::Loggable
    attr_accessor :name, :threads, :environment, :pidfile, :directory, :quiet, :log_level, :log_file

    def initialize(argv)
      @name        = nil
      @threads     = nil
      @quiet       = false
      @environment = nil
      @pidfile     = nil
      @directory   = '.'
      @log_level   = nil
      @log_file    = nil
      parse(argv)
    end

    # Run a RocketJob::Worker from the command line
    def run
      Thread.current.name = 'rocketjob main'
      setup_environment
      setup_logger
      rails? ? boot_rails : boot_standalone
      write_pidfile

      opts               = {}
      opts[:name]        = name if name
      opts[:max_threads] = threads if threads
      Worker.run(opts)
    end

    def rails?
      @rails ||= begin
        boot_file = Pathname.new(directory).join('config/environment.rb').expand_path
        boot_file.file?
      end
    end

    # Initialize the Rails environment
    # Returns [true|false] whether Rails is present
    def boot_rails
      logger.info "Loading Rails environment: #{environment}"

      boot_file = Pathname.new(directory).join('config/environment.rb').expand_path
      require(boot_file.to_s)

      begin
        require 'rails_semantic_logger'
      rescue LoadError
        raise "Add the following line to your Gemfile when running rails:\n gem 'rails_semantic_logger'"
      end

      # Override Rails log level if command line option was supplied
      SemanticLogger.default_level = log_level.to_sym if log_level

      if Rails.configuration.eager_load
        RocketJob::Worker.logger.measure_info('Eager loaded Rails and all Engines') do
          Rails.application.eager_load!
          Rails::Engine.subclasses.each(&:eager_load!)
        end
      end
    end

    # In a standalone environment, explicitly load config files
    def boot_standalone
      # Try to load bundler if present
      begin
        require 'bundler/setup'
        Bundler.require(environment)
      rescue LoadError
      end

      require 'rocketjob'
      begin
        require 'rocketjob_pro'
      rescue LoadError
      end

      # Log to file except when booting rails, when it will add the log file path
      path = log_file ? Pathname.new(log_file) : Pathname.pwd.join("log/#{environment}.log")
      path.dirname.mkpath
      SemanticLogger.add_appender(path.to_s, &SemanticLogger::Appender::Base.colorized_formatter)

      logger.info "Rails not detected. Running standalone: #{environment}"
      RocketJob::Config.load!(environment)
      self.class.eager_load_jobs
    end

    # Create a PID file if requested
    def write_pidfile
      return unless pidfile
      pid = $PID
      File.open(pidfile, 'w') { |f| f.puts(pid) }

      # Remove pidfile on exit
      at_exit do
        File.delete(pidfile) if pid == $PID
      end
    end

    def setup_environment
      # Override Env vars when environment is supplied
      if environment
        ENV['RACK_ENV'] = ENV['RAILS_ENV'] = environment
      else
        self.environment = ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'
      end
    end

    def setup_logger
      SemanticLogger.add_appender(STDOUT, &SemanticLogger::Appender::Base.colorized_formatter) unless quiet
      SemanticLogger.default_level = log_level.to_sym if log_level

      # Enable SemanticLogger signal handling for this process
      SemanticLogger.add_signal_handler
    end

    # Eager load files in jobs folder
    def self.eager_load_jobs(path = 'jobs')
      Pathname.glob("#{path}/**/*.rb").each do |path|
        next if path.directory?
        logger.debug "Loading #{path.to_s}"
        load path.expand_path.to_s
      end
    end

    # Parse command line options placing results in the corresponding instance variables
    def parse(argv)
      parser        = OptionParser.new do |o|
        o.on('-n', '--name NAME', 'Unique Name of this worker instance (Default: host_name:PID)') do |arg|
          @name = arg
        end
        o.on('-t', '--threads COUNT', 'Number of worker threads to start') do |arg|
          @threads = arg.to_i
        end
        o.on('-q', '--quiet', 'Do not write to stdout, only to logfile. Necessary when running as a daemon') do
          @quiet = true
        end
        o.on('-d', '--dir DIR', 'Directory containing Rails app, if not current directory') do |arg|
          @directory = arg
        end
        o.on('-e', '--environment ENVIRONMENT', 'The environment to run the app on (Default: RAILS_ENV || RACK_ENV || development)') do |arg|
          @environment = arg
        end
        o.on('-l', '--log_level trace|debug|info|warn|error|fatal', 'The log level to use') do |arg|
          @log_level = arg
        end
        o.on('-f', '--log_file FILE_NAME', 'The log file to write to. Default: log/<environment>.log') do |arg|
          @log_file = arg
        end
        o.on('--pidfile PATH', 'Use PATH as a pidfile') do |arg|
          @pidfile = arg
        end
        o.on('-v', '--version', 'Print the version information') do
          puts "Rocket Job v#{RocketJob::VERSION}"
          exit 1
        end
      end
      parser.banner = 'rocketjob <options>'
      parser.on_tail '-h', '--help', 'Show help' do
        puts parser
        exit 1
      end
      parser.parse! argv
    end

  end
end
