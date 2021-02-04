require "concurrent"
module RocketJob
  # ThreadWorker
  #
  # A worker runs on a single operating system thread.
  # Is usually started under a Rocket Job server process.
  class ThreadWorker < Worker
    attr_reader :thread

    def initialize(id:, server_name:)
      super(id: id, server_name: server_name)
      @shutdown = Concurrent::Event.new
      @thread   = Thread.new { run }
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
