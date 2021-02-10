module RocketJob
  # Run each worker in its own "Ractor".
  class RactorWorker < Worker
    attr_reader :thread

    def initialize(id:, server_name:)
      super(id: id, server_name: server_name)
      @shutdown = Concurrent::Event.new
      @thread   = Ractor.new(name: "rocketjob-#{id}") { run }
    end

    def alive?
      @thread.alive?
    end

    def backtrace
      @thread.backtrace
    end

    def join(*args)
      @thread.join(*args)
    end

    # Send each active worker the RocketJob::ShutdownException so that stops processing immediately.
    def kill
      @thread.raise(Shutdown, "Shutdown due to kill request for worker: #{name}") if @thread.alive?
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
