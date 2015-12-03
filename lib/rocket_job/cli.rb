require 'optparse'
require 'yaml'
module RocketJob
  # Command Line Interface parser for RocketJob
  class CLI
    include SemanticLogger::Loggable
    attr_accessor :name, :threads, :environment, :pidfile, :directory, :quiet, :log_level

    def initialize(argv)
      @name        = nil
      @threads     = nil
      @quiet       = false
      @environment = nil
      @pidfile     = nil
      @directory   = '.'
      @log_level   = nil
      parse(argv)
    end

    # Run a RocketJob::Worker from the command line
    def run
      Thread.current.name = 'rocketjob main'
      setup_environment
      setup_logger
      boot_standalone unless boot_rails
      write_pidfile

      opts               = {}
      opts[:name]        = name if name
      opts[:max_threads] = threads if threads
      Worker.run(opts)
    end

    # Initialize the Rails environment
    # Returns [true|false] whether Rails is present
    def boot_rails
      boot_file = Pathname.new(directory).join('config/environment.rb').expand_path
      return false unless boot_file.file?

      logger.info 'Booting Rails'
      require boot_file.to_s
      if Rails.configuration.eager_load
        RocketJob::Worker.logger.benchmark_info('Eager loaded Rails and all Engines') do
          Rails.application.eager_load!
          Rails::Engine.subclasses.each(&:eager_load!)
        end
      end

      self.class.load_config(Rails.env)
      true
    end

    def boot_standalone
      logger.info 'Rails not detected. Running standalone.'
      self.class.load_config(environment)
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
    end

    # Configure MongoMapper if it has not already been configured
    def self.load_config(environment='development', file_name=nil)
      return false if MongoMapper.config

      config_file = file_name ? Pathname.new(file_name) : Pathname.pwd.join('config/mongo.yml')
      if config_file.file?
        config = YAML.load(ERB.new(config_file.read).result)
        log    = SemanticLogger::DebugAsTraceLogger.new('Mongo')
        MongoMapper.setup(config, environment, logger: log)
        true
      else
        raise(ArgumentError, "Mongo Configuration file: #{config_file.to_s} not found")
      end
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
        o.on('-n', '--name NAME', 'Unique Name of this worker instance (Default: hostname:PID)') { |arg| @name = arg }
        o.on('-t', '--threads COUNT', 'Number of worker threads to start') { |arg| @threads = arg.to_i }
        o.on('-q', '--quiet', 'Do not write to stdout, only to logfile. Necessary when running as a daemon') { @quiet = true }
        o.on('-d', '--dir DIR', 'Directory containing Rails app, if not current directory') { |arg| @directory = arg }
        o.on('-e', '--environment ENVIRONMENT', 'The environment to run the app on (Default: RAILS_ENV || RACK_ENV || development)') { |arg| @environment = arg }
        o.on('-l', '--log_level trace|debug|info|warn|error|fatal', 'The log level to use') { |arg| @log_level = arg }
        o.on('--pidfile PATH', 'Use PATH as a pidfile') { |arg| @pidfile = arg }
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
