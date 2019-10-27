module RocketJob
  class Railtie < Rails::Railtie
    # Exposes Rocket Job's configuration to the Rails application configuration.
    #
    # @example Set up configuration in the Rails app.
    #   module MyApplication
    #     class Application < Rails::Application
    #       # The maximum number of workers to create on any one server. (Default: 10)
    #       config.rocket_job.max_workers = config.secret_config("rocket_job/max_workers", type: :integer, default: 10)
    #
    #       # Number of seconds between heartbeats from a Rocket Job Server process. (Default: 15)
    #       config.rocket_job.heartbeat_seconds = config.secret_config("rocket_job/heartbeat_seconds", type: :float, default: 15.0)
    #
    #       # Maximum number of seconds a Worker will wait before checking for new jobs. (Default: 5)
    #       config.rocket_job.max_poll_seconds = config.secret_config("rocket_job/max_poll_seconds", type: :float, default: 5.0)
    #
    #       # Number of seconds between checking for:
    #       # - Jobs with a higher priority
    #       # - If the current job has been paused, or aborted
    #       #
    #       # Making this interval too short results in too many checks for job status
    #       # changes instead of focusing on completing the active tasks
    #       #
    #       # Note:
    #       #   Not all job types support pausing in the middle
    #       # Default: 60 seconds between checks.
    #       config.rocket_job.re_check_seconds = config.secret_config("rocket_job/re_check_seconds", type: :float, default: 60.0)
    #
    #       config.rocket_job.include_filter    = config.secret_config["rocket_job/include_filter"]
    #       config.rocket_job.exclude_filter    = config.secret_config["rocket_job/exclude_filter"]
    #       config.rocket_job.where_filter      = config.secret_config["rocket_job/where_filter"]
    #     end
    #   end
    config.rocket_job = Config
  end
end
