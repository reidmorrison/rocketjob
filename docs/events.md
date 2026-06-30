---
layout: default
---

# Events
{:.no_toc}

Near real-time control of running Rocket Job servers, and a general purpose
publish / subscribe mechanism for your own application.

**Contents**

* TOC
{:toc}

## Overview

A Rocket Job event is a small message that is published to MongoDB and then
delivered almost immediately (usually under 100 ms) to every process that has
subscribed to it. There is no separate message broker to install or operate:
events are stored in a [tailable capped collection](architecture.html) that
every Rocket Job server tails in the background.

Events are how the supervisor controls its servers. When a server is paused,
stopped, or killed from [Mission Control](mission_control.html) or from a Rails
console, an event is published and the running servers react to it right away.
Because delivery is near instantaneous across every server in the cluster,
managing a fleet of servers feels immediate instead of waiting for the next
poll interval.

Events are not limited to managing Rocket Job. Any process running in the same
application can publish events, and your own code can subscribe to both the
built-in events and to events that you define yourself.

An event has three parts:

* a **name** that identifies the subscriber it is destined for,
* an **action**, which is the method invoked on the subscriber, and
* an optional hash of **parameters** passed to that method as keyword arguments.

Publishing an event is as simple as calling `publish` on a subscriber class:

~~~ruby
RocketJob::Subscribers::Server.publish(:pause)
~~~

This can be run from a Rails console, a Rails web application, or anywhere else
in the same application that is connected to the same MongoDB.

## Built-in Subscribers

Rocket Job ships with the following subscribers. Every running server
automatically subscribes to all of them on startup, so the events below are
ready to use without any additional configuration on the servers.

### Controlling the Log Level

The most useful built-in event is changing the log level of a running
application at runtime, without restarting any process or deploying any code.
This is invaluable for diagnosing a problem in production: turn on `:debug` or
`:trace` logging, capture what you need, then turn it back down again.

Rocket Job uses [Semantic Logger](https://logger.rocketjob.io), so the log
level can be changed globally, for a single class, or targeted at a single host
or process.

Change the global log level to `:debug` on every server:

~~~ruby
RocketJob::Subscribers::Logger.publish(:set, level: :debug)
~~~

Change it back to `:info` everywhere:

~~~ruby
RocketJob::Subscribers::Logger.publish(:set, level: :info)
~~~

Change the log level for a single class across all servers. This is the most
precise way to increase logging: turn up just the class you are investigating
and leave everything else quiet.

~~~ruby
RocketJob::Subscribers::Logger.publish(:set, level: :trace, class_name: "RocketJob::Supervisor")
~~~

The targeting arguments narrow which processes respond. Change the log level on
just one host:

~~~ruby
RocketJob::Subscribers::Logger.publish(:set, level: :debug, host_name: "server1.company.com")
~~~

Or on one specific process, by host name and process id:

~~~ruby
RocketJob::Subscribers::Logger.publish(:set, level: :debug, host_name: "server1.company.com", pid: 34567)
~~~

`class_name` and the `host_name` / `pid` targeting can be combined, for example
to raise the log level for a single class on a single process.

When workers appear to be stuck or hanging, ask them to write the backtrace of
every thread to their log file. This is one of the quickest ways to see what a
process is actually doing.

Dump every thread's backtrace on all servers:

~~~ruby
RocketJob::Subscribers::Logger.publish(:thread_dump)
~~~

Or on just one host:

~~~ruby
RocketJob::Subscribers::Logger.publish(:thread_dump, host_name: "server1.company.com")
~~~

### Managing Servers

`RocketJob::Subscribers::Server` controls running servers. By default an event
applies to every server; supply `server_id` or `name` to target one.

Stop all running servers gracefully, letting active jobs and slices finish:

~~~ruby
RocketJob::Subscribers::Server.publish(:stop)
~~~

Pause all running servers. Paused servers stop picking up new work but stay
alive:

~~~ruby
RocketJob::Subscribers::Server.publish(:pause)
~~~

Resume all paused servers:

~~~ruby
RocketJob::Subscribers::Server.publish(:resume)
~~~

Hard kill all servers immediately, without waiting for active jobs or slices to
complete:

~~~ruby
RocketJob::Subscribers::Server.publish(:kill)
~~~

Tell every server to refresh, re-evaluating its state immediately rather than
waiting for the next poll:

~~~ruby
RocketJob::Subscribers::Server.publish(:refresh)
~~~

Write the backtrace of every worker thread on every server to its log file,
useful for researching jobs or slices that appear to be stuck:

~~~ruby
RocketJob::Subscribers::Server.publish(:thread_dump)
~~~

**Targeting a single server.** Instead of acting on every server, supply the
server's `id` or `name`. Look up the server by its host name, then publish the
event with its id:

~~~ruby
server = RocketJob::Server.where(name: "myhost").first
RocketJob::Subscribers::Server.publish(:stop, server_id: server.id)
~~~

The `server_id` (or `name`) argument can be applied to any of the server events
above.

### Managing Individual Workers

`RocketJob::Subscribers::Worker` controls a single worker thread on a single
server. These events require both `server_id` and `worker_id`.

Stop worker `1` on the server named `myhost`:

~~~ruby
server = RocketJob::Server.where(name: "myhost").first
RocketJob::Subscribers::Worker.publish(:stop, worker_id: 1, server_id: server.id)
~~~

Kill a worker that is hanging:

~~~ruby
RocketJob::Subscribers::Worker.publish(:kill, worker_id: 1, server_id: server.id)
~~~

Write a single worker's thread backtrace to its log file:

~~~ruby
RocketJob::Subscribers::Worker.publish(:thread_dump, worker_id: 1, server_id: server.id)
~~~

### Refreshing Secret Config

When running Rocket Job in a container it is recommended to manage settings and
application credentials with [Secret Config](https://config.rocketjob.io).
Rocket Job ships with a subscriber that refreshes every server's in-memory copy
of the Secret Config registry, so updated settings take effect without a
restart:

~~~ruby
RocketJob::Subscribers::SecretConfig.publish(:refresh)
~~~

Secret Config can also configure Rocket Job itself. For example, add the
following to `config/application.rb`:

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

## Subscribing from Other Processes

Rocket Job servers subscribe to the built-in events automatically. Any other
process that should respond to events, such as a Rails web application or a
Rails console, needs to subscribe to the events it cares about and start a
listener thread.

Add the following to `config/initializers/rocket_job.rb`:

~~~ruby
unless RocketJob.server?
  # Subscribe to logging events so that log levels can be changed in this process
  RocketJob::Subscribers::Logger.subscribe

  # Subscribe to Secret Config events
  RocketJob::Subscribers::SecretConfig.subscribe if defined?(SecretConfig)

  # Start the Rocket Job event listener thread
  Thread.new { RocketJob::Event.listener }
end
~~~

The `unless RocketJob.server?` guard ensures this only runs in non-server
processes, since servers already subscribe and run the listener themselves.

A process only reacts to the events it has subscribed to. The example above
subscribes a web application to the Logger and Secret Config events, so a log
level change published from anywhere in the application takes effect in the web
process too.

## Custom Events

Events are a general purpose publish / subscribe mechanism. Your own
application can define subscribers to perform custom actions across every
process: clearing a connection pool, flushing a cache, reloading a feature
flag, or anything else that should happen everywhere at once.

A subscriber is any class that includes `RocketJob::Subscriber`. Each public
method is an action that can be published. Method arguments become the event's
parameters, and are passed as keyword arguments:

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

Register the subscriber in an initializer, for example
`config/initializers/rocket_job.rb`, so the processes that should respond to it
subscribe on startup:

~~~ruby
ExampleSubscriber.subscribe
~~~

From a Rails console or web application, invoke the action on every subscribed
process:

~~~ruby
ExampleSubscriber.publish(:example)
~~~

Pass parameters as keyword arguments. They are delivered to the action method:

~~~ruby
ExampleSubscriber.publish(:example2, name: "Jack", port: 123)
~~~

Subscribers can also take constructor arguments. Anything passed to `subscribe`
is forwarded to the subscriber's `new`, which is how the built-in `Server` and
`Worker` subscribers receive their supervisor.

## How It Works

Events are published by saving a small document into the `rocket_job.events`
capped collection in MongoDB. Every subscribed process tails that collection
with a long-polling tailable cursor, so a newly published event is picked up
within milliseconds and the matching action is invoked on each subscriber.

Because the mechanism relies on a tailable capped collection, it requires a real
MongoDB server. AWS DocumentDB does not support capped collections and therefore
cannot host Rocket Job. See [Installation](installation.html) and
[Architecture](architecture.html) for details.

A subscriber receives only the events whose name matches its own. An action that
is published but is not defined on any subscribed subscriber is simply logged
and ignored, so it is safe to publish an event before every process has been
upgraded to handle it.
