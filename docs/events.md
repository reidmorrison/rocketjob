---
layout: default
---

# Rocket Job Events

Rocket Job uses events internally to manage running servers.

For example, when pausing, stopping, etc. servers via the Rocket Job Web Interface, it publishes an event that
servers are configured to respond to. 

Since events happen immediately (< 100 ms) across all Rocket Job Servers, this makes server management far more 
responsive.

Events can be published from a Rails Console in the same rails environment as the running Rocket Job servers,
or can be published from a web application that is part of the same application.

## Standard Events

### Server Management

Stop all running Rocket Job servers:

~~~ruby
RocketJob::Subscribers::Server.publish(:stop)
~~~

Pause all running Rocket Job servers:

~~~ruby
RocketJob::Subscribers::Server.publish(:pause)
~~~

Resume all paused Rocket Job servers:

~~~ruby
RocketJob::Subscribers::Server.publish(:resume)
~~~

Hard kill all active Rocket Job servers immediately without waiting for active jobs or slices to complete.

~~~ruby
RocketJob::Subscribers::Server.publish(:kill)
~~~

Write the thread backtrace for all worker threads running on all servers to its log file. 

~~~ruby
RocketJob::Subscribers::Server.publish(:thread_dump)
~~~

Thread backtraces are useful for researching why jobs or slices are "stuck" or "hanging".

#### Arguments

Instead of sending an event for all servers to process, the server id can be used to specify which server
to execute the event on.

For example, to stop a specific server, lookup its `id` using its host name, then publish the event with that id:

~~~ruby
server = RocketJob::Server.where(name: "myhost").first
RocketJob::Subscribers::Server.publish(:stop, server_id: server.id)
~~~

The `server_id` can be applied to all of the above server events.

### Worker Management

Individual workers on Rocket Job servers can be managed separately.

To manage a specific worker, lookup the `id` of the server it is running on. Then in combination with its worker
number it can be managed.

For example, stop worker `1` on the Rocket Job server with host name: `myhost`:

~~~ruby
server = RocketJob::Server.where(name: "myhost").first
RocketJob::Subscribers::Worker.publish(:stop, worker_id: 1, server_id: server.id)
~~~

Similarly, the worker can be killed, when it is hanging:

~~~ruby
RocketJob::Subscribers::Worker.publish(:kill, worker_id: 1, server_id: server.id)
~~~

Similarly, the worker's backtrace can be written to its log file:

~~~ruby
RocketJob::Subscribers::Worker.publish(:thread_dump, worker_id: 1, server_id: server.id)
~~~

### Semantic Logger

The log level of a running application can be modified at runtime without restarting any code by using the
[Semantic Logger](https://logger.rocketjob.io) change log level event.

Change the global log level to `debug` on all servers.

~~~ruby
RocketJob::Subscribers::Logger.publish(:set, level: :debug)
~~~

Change the global log level to `info` on all servers.

~~~ruby
RocketJob::Subscribers::Logger.publish(:set, level: :info)
~~~

Change the log level to `debug` for all process on a specific host:

~~~ruby
RocketJob::Subscribers::Logger.publish(:set, level: :debug, host_name: "server1.company.com")
~~~

Change the log level to `debug` for a specific process id:

~~~ruby
RocketJob::Subscribers::Logger.publish(:set, level: :debug, host_name: "server1.company.com", pid: 34567)
~~~

Change the log level for a specific class across all servers.

~~~ruby
RocketJob::Subscribers::Logger.publish(:set, level: :debug, class_name: "RocketJob::Supervisor")
~~~

When workers are stuck / hanging, it is useful to get them to dump their backtrace to the log file.

Dump the thread backtrace for every thread, on a particular host to the log file:
~~~ruby
RocketJob::Subscribers::Logger.publish(:thread_dump, host_name: 'f98558c72ef7')
~~~

### Secret Config

When running Rocket Job inside a docker container it is also recommended to run [Secret Config](https://config.rocketjob.io) to manage all
settings and application credentials. Rocket Job has built-in support for the following Secret Config events:

Refresh Secret Config settings across all Rocket Job servers:

~~~ruby
RocketJob::Subscribers::SecretConfig.publish(:refresh)
~~~

When running Secret Config, it can also be used to configure Rocket Job itself.

For example, add the following lines to `config/application.rb`:

~~~ruby
# Limit this server to only those job classes that match this regular expression (case-insensitive).
# Example: "DirmonJob|WeeklyReportJob"
if config.secret_config.key?("rocket_job/include_filter")
  config.rocket_job.include_filter = Regexp.new(config.secret_config.fetch("rocket_job/include_filter"), true)
end

# Prevent this server from working on any job classes that match this regular expression (case-insensitive).
# Example: "DirmonJob|WeeklyReportJob"
if config.secret_config.key?("rocket_job/exclude_filter")
  config.rocket_job.exclude_filter = Regexp.new(config.secret_config.fetch("rocket_job/exclude_filter"), true)
end

# Limit this server instance to the supplied mongo query filter. Supply as a string in JSON format.
# Example: '{\"priority\":{\"$lte\":25}}'"
config.rocket_job.where_filter      = config.secret_config.fetch("rocket_job/where_filter", type: :json, default: nil)
config.rocket_job.max_workers       = config.secret_config.fetch("rocket_job/max_workers", type: :integer, default: 10)
config.rocket_job.heartbeat_seconds = config.secret_config.fetch("rocket_job/heartbeat_seconds", type: :float, default: 15.0)
config.rocket_job.max_poll_seconds  = config.secret_config.fetch("rocket_job/max_poll_seconds", type: :float, default: 5.0)
config.rocket_job.re_check_seconds  = config.secret_config.fetch("rocket_job/re_check_seconds", type: :float, default: 60.0)
~~~

## Subscribing to events

All Rocket Job servers automatically subscribe to these events on startup. To subscribe to these events from a Rails
application in the same environment, for example a Rails web application, or a Rails console, 
add the following to `config/initializers/rocket_job.rb`:

~~~ruby
unless RocketJob.server?
  # Subscribe to logging events so that log levels can be changed in this process
  RocketJob::Subscribers::Logger.subscribe
  
  # Start the Rocket Job Event listener thread
  Thread.new { RocketJob::Event.listener }
end
~~~

## User defined Events

User defined events can be used to send events to all of the servers to perform a custom action.

~~~ruby
class ExampleSubscriber
  include RocketJob::Subscriber

  def example
    logger.measure_info "Running example event" do
      puts "Put some custom code here, for example to clear out connection pools, etc..."
    end
  end
  
  def example2(name:, port:)
    logger.measure_info "Running example2 event" do
      puts "Example2 name: #{name}, port: #{port}"
    end
  end
end
~~~

To register the example subscriber, add the following to an initializer, for example `config/initializers/rocket_job.rb`:

~~~ruby
ExampleSubscriber.subscribe
~~~

From a Rails console, or from within a Rails web application, to invoke the above event on all servers:

~~~ruby
ExampleSubscriber.publish(:example)
~~~

For example when the event can take arguments

~~~ruby
ExampleSubscriber.publish(:example2, name: "Jack", port: 123)
~~~
