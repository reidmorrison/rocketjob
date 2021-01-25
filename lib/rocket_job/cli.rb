require "optparse"
require "json"
require "semantic_logger"
require "mongoid"
require "rocketjob"
require "pathname"
module RocketJob
  # Command Line Interface parser for Rocket Job
  class CLI
    include SemanticLogger::Loggable
    attr_accessor :environment, :pidfile, :directory, :quiet,
                  :log_level, :log_file, :mongo_config, :symmetric_encryption_config,
                  :max_workers, :include_filter, :exclude_filter, :where_filter, :server,
                  :stop_server, :kill_server, :pause_server, :resume_server, :thread_dump, :list_servers, :refresh

    def initialize(argv)
      @server                      = true
      @quiet                       = false
      @environment                 = nil
      @pidfile                     = nil
      @directory                   = "."
      @log_level                   = nil
      @log_file                    = nil
      @mongo_config                = nil
      @symmetric_encryption_config = nil
      @include_filter              = nil
      @exclude_filter              = nil
      @stop_server                 = nil
      @kill_server                 = nil
      @pause_server                = nil
      @resume_server               = nil
      @thread_dump                 = nil
      @list_servers                = nil
      parse(argv)
    end

    # Run a RocketJob::Server from the command line
    def run
      Thread.current.name = "rocketjob main"
      RocketJob.server! if server
      setup_environment
      setup_logger
      rails? ? boot_rails : boot_standalone
      override_config
      write_pidfile

      # In case Rails did not load the Mongoid Config
      RocketJob::Config.load!(environment, mongo_config, symmetric_encryption_config) if ::Mongoid::Config.clients.empty?

      return perform_server_action(stop_server, :stop) if stop_server
      return perform_server_action(kill_server, :kill) if kill_server
      return perform_server_action(pause_server, :pause) if pause_server
      return perform_server_action(resume_server, :resume) if resume_server
      return perform_server_action(thread_dump, :thread_dump) if thread_dump
      return perform_list_servers(list_servers) if list_servers

      Supervisor.run
    end

    def rails?
      @rails ||=
        begin
          boot_file = Pathname.new(directory).join("config/environment.rb").expand_path
          boot_file.file?
        end
    end

    # Initialize the Rails environment
    # Returns [true|false] whether Rails is present
    def boot_rails
      logger.info "Loading Rails environment: #{environment}"
      RocketJob.rails!

      require "rails"
      require "rocket_job/railtie"
      boot_file = Pathname.new(directory).join("config/environment.rb").expand_path
      require(boot_file.to_s)

      begin
        require "rails_semantic_logger"
      rescue LoadError
        raise "Add the following line to your Gemfile when running rails:\n gem 'rails_semantic_logger'"
      end

      # Override Rails log level if command line option was supplied
      SemanticLogger.default_level = log_level.to_sym if log_level

      return unless Rails.configuration.eager_load

      logger.measure_info("Eager loaded Rails and all Engines") do
        Rails.application.eager_load!
        Rails::Engine.subclasses.each(&:eager_load!)
        self.class.eager_load_jobs(File.expand_path("jobs", File.dirname(__FILE__)))
      end
    end

    # In a standalone environment, explicitly load config files
    def boot_standalone
      # Try to load bundler if present
      begin
        require "bundler/setup"
        Bundler.require(environment)
      rescue LoadError
        nil
      end

      require "rocketjob"

      # Log to file except when booting rails, when it will add the log file path
      path = log_file ? Pathname.new(log_file) : Pathname.pwd.join("log/#{environment}.log")
      path.dirname.mkpath
      SemanticLogger.add_appender(file_name: path.to_s, formatter: :color)

      logger.info "Rails not detected. Running standalone: #{environment}"
      RocketJob::Config.load!(environment, mongo_config, symmetric_encryption_config)
      self.class.eager_load_jobs(File.expand_path("jobs", File.dirname(__FILE__)))
      self.class.eager_load_jobs
    end

    # Allow the CLI to override the configuration after rails has been loaded.
    def override_config
      Config.max_workers    = max_workers if max_workers
      Config.include_filter = include_filter if include_filter
      Config.exclude_filter = exclude_filter if exclude_filter
      Config.where_filter   = where_filter if where_filter
    end

    # Create a PID file if requested
    def write_pidfile
      return unless pidfile

      pid = $PID
      File.open(pidfile, "w") { |f| f.puts(pid) }

      # Remove pidfile on exit
      at_exit do
        File.delete(pidfile) if pid == $PID
      end
    end

    def setup_environment
      # Override Env vars when environment is supplied
      if environment
        ENV["RACK_ENV"] = ENV["RAILS_ENV"] = environment
      else
        self.environment = ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development"
      end
    end

    def setup_logger
      SemanticLogger.add_appender(io: STDOUT, formatter: :color) unless quiet
      SemanticLogger.default_level = log_level.to_sym if log_level

      # Enable SemanticLogger signal handling for this process
      SemanticLogger.add_signal_handler

      ::Mongoid.logger       = SemanticLogger[::Mongoid]
      ::Mongo::Logger.logger = SemanticLogger[::Mongo]
    end

    # Eager load files in jobs folder
    def self.eager_load_jobs(job_path = "jobs")
      Pathname.glob("#{job_path}/**/*.rb").each do |path|
        next if path.directory?

        logger.debug "Loading #{path}"
        require path.expand_path.to_s
      end
    end

    def perform_list_servers(filter)
      return list_the_servers(filter) unless refresh

      loop do
        list_the_servers(filter)
        sleep(refresh)
        puts
      end
    end

    def list_the_servers(filter)
      layout = "%50.50s %20.20s %20.20s %20.20s %10.10s"
      puts format(layout, "Server Name", "Workers(Current/Max)", "Started", "Heartbeat", "State")
      header = "=" * 50
      puts format(layout, header, header, header, header, header)
      query = filter == :all ? RocketJob::Server.all : RocketJob::Server.where(name: /#{filter}/)
      query.each do |server|
        workers   = "#{server&.heartbeat&.workers}/#{server.max_workers}"
        duration  = Time.now - (server.started_at || Time.now)
        started   = "#{RocketJob.seconds_as_duration(duration)} ago"
        duration  = Time.now - (server&.heartbeat&.updated_at || Time.now)
        heartbeat = "#{RocketJob.seconds_as_duration(duration)} ago"
        puts format(layout, server.name, workers, started, heartbeat, server.state)
      end
      0
    end

    def perform_server_action(server_name, action)
      server_ids(server_name).each { |server_id| RocketJob::Subscribers::Server.publish(action, server_id: server_id) }
      # RocketJob::Subscribers::Worker.publish(:stop, worker_id: 1, server_id: RocketJob::Server.running.last.id)
      0
    end

    # Returns server ids for the supplied exact server name, or partial match.
    #
    # When no ':' is supplied a partial hostname lookup is performed.
    #
    # Example: Exact server name (hostname and pid) match:
    #   "9cdbe7e995bc:1"
    #
    # Example: Matches all servers that contain the string '.batch.user.org':
    #   ".batch.user.org"
    def server_ids(server_name)
      raise(ArgumentError, "Missing server name") unless server_name

      return [nil] if server_name == :all

      hostname, pid = server_name.split(":")
      raise(ArgumentError, "Missing server name in: #{server_name}") unless hostname

      if pid
        server = RocketJob::Server.where(name: server_name).first
        raise(ArgumentError, "No server with exact name: #{server_name} was found.") unless server

        return [server.id]
      end

      server_ids = RocketJob::Server.where(name: /#{hostname}/).collect(&:id)
      raise(ArgumentError, "No server with partial name: #{server_name} was found.") if server_ids.empty?

      server_ids
    end

    # Parse command line options placing results in the corresponding instance variables
    def parse(argv)
      parser = OptionParser.new do |o|
        o.on("-n", "--name NAME", "Unique Name of this server (Default: host_name:PID)") do |arg|
          Config.name = arg
        end
        o.on("-w", "--workers COUNT", "Number of workers (threads) to start") do |arg|
          @max_workers = arg.to_i
        end
        o.on("--include REGEXP",
             'Limit this server to only those job classes that match this regular expression (case-insensitive). Example: "DirmonJob|WeeklyReportJob"') do |arg|
          @include_filter = Regexp.new(arg, true)
        end
        o.on("-E", "--exclude REGEXP",
             'Prevent this server from working on any job classes that match this regular expression (case-insensitive). Example: "DirmonJob|WeeklyReportJob"') do |arg|
          @exclude_filter = Regexp.new(arg, true)
        end
        o.on("-W", "--where JSON",
             "Limit this server instance to the supplied mongo query filter. Supply as a string in JSON format. Example: '{\"priority\":{\"$lte\":25}}'") do |arg|
          @where_filter = JSON.parse(arg)
        end
        o.on("-q", "--quiet", "Do not write to stdout, only to logfile. Necessary when running as a daemon") do
          @quiet = true
        end
        o.on("-d", "--dir DIR", "Directory containing Rails app, if not current directory") do |arg|
          @directory = arg
        end
        o.on("-e", "--environment ENVIRONMENT",
             "The environment to run the app on (Default: RAILS_ENV || RACK_ENV || development)") do |arg|
          @environment = arg
        end
        o.on("-l", "--log_level trace|debug|info|warn|error|fatal", "The log level to use") do |arg|
          @log_level = arg
        end
        o.on("-f", "--log_file FILE_NAME", "The log file to write to. Default: log/<environment>.log") do |arg|
          @log_file = arg
        end
        o.on("--pidfile PATH", "Use PATH as a pidfile") do |arg|
          @pidfile = arg
        end
        o.on("-m", "--mongo MONGO_CONFIG_FILE_NAME", "Path and filename of config file. Default: config/mongoid.yml") do |arg|
          @mongo_config = arg
        end
        o.on("-s", "--symmetric-encryption SYMMETRIC_ENCRYPTION_CONFIG_FILE_NAME",
             "Path and filename of Symmetric Encryption config file. Default: config/symmetric-encryption.yml") do |arg|
          @symmetric_encryption_config = arg
        end
        o.on("--list [FILTER]",
             "List active servers. Supply either an exact server name or a partial name as a filter.") do |filter|
          @quiet        = true
          @server       = false
          @list_servers = filter || :all
        end
        o.on("--refresh [SECONDS]",
             "When listing active servers, update the list by this number of seconds. Defaults to every 1 second.") do |seconds|
          @refresh = (seconds || 1).to_s.to_f
        end
        o.on("--stop [SERVER_NAME]",
             "Send event to stop a server once all in-process workers have completed. Optionally supply the complete or partial name of the server(s) to stop. Default: All servers.") do |server_name|
          @quiet       = true
          @server      = false
          @stop_server = server_name || :all
        end
        o.on("--kill [SERVER_NAME]",
             "Send event to hard kill a server. Optionally supply the complete or partial name of the server(s) to kill. Default: All servers.") do |server_name|
          @quiet       = true
          @server      = false
          @kill_server = server_name || :all
        end
        o.on("--pause [SERVER_NAME]",
             "Send event to pause a server. Optionally supply the complete or partial name of the server(s) to pause. Default: All servers.") do |server_name|
          @quiet        = true
          @server       = false
          @pause_server = server_name || :all
        end
        o.on("--resume [SERVER_NAME]",
             "Send event to resume a server. Optionally supply the complete or partial name of the server(s) to resume. Default: All servers.") do |server_name|
          @quiet         = true
          @server        = false
          @resume_server = server_name || :all
        end
        o.on("--dump [SERVER_NAME]",
             "Send event for a server to send a worker thread dump to its log file. Optionally supply the complete or partial name of the server(s). Default: All servers.") do |server_name|
          @quiet       = true
          @server      = false
          @thread_dump = server_name || :all
        end
        o.on("-v", "--version", "Print the version information") do
          puts "Rocket Job v#{RocketJob::VERSION}"
          exit 1
        end
      end
      parser.banner = "rocketjob <options>"
      parser.on_tail "-h", "--help", "Show help" do
        puts parser
        exit 1
      end
      parser.parse! argv
    end
  end
end
