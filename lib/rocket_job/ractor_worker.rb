module RocketJob
  # Run each worker in its own "Ractor".
  class RactorWorker < Worker
    attr_reader :ractor

    def initialize(id:, server_name:)
      super(id: id, server_name: server_name)
      @shutdown = Concurrent::Event.new
      @ractor   = Ractor.new(name: "rocketjob-#{id}") { run }
    end

    def alive?
      @ractor.alive?
    end

    def backtrace
      @ractor.backtrace
    end

    def join(*args)
      @ractor.join(*args)
    end

    # Send each active worker the RocketJob::ShutdownException so that stops processing immediately.
    def kill
      return false unless alive?

      @ractor.raise(Shutdown, "Shutdown due to kill request for worker: #{name}")
      true
    end

    def shutdown?
      @shutdown.set?
    end

    def shutdown!
      @shutdown.set
    end

    # Returns [true|false] whether the shutdown indicator was set
    def wait_for_shutdown?(timeout = nil)
      @shutdown.wait(timeout)
    end
  end
end
