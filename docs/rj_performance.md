---
layout: default
---
## Rocket Job Performance Test

Setup for the performance test below:

* 13" MacBook Pro (Dual core i7, Early 2015)
* Mac OSX v10.11
* Ruby v2.3 (MRI/CRuby)
* MongoDB v3.2.1

### Start worker processes:

Run the following command in 3 separate windows:

~~~
bundle exec rocketjob --log_level warn --threads 5
~~~

Quick test:

~~~
bundle exec rocketjob_perf -c 1000
~~~

Full test:

~~~
bundle exec rocketjob_perf
~~~

### Test 1

The following results were obtained when running 3 Rocket Job processes.

~~~
Running: 5 workers, distributed across 3 processes
Waiting for workers to pause
Enqueuing jobs
Resuming workers
{
  :count=>100000,
  :duration=>108.629,
  :jobs_per_second=>920
}
~~~

920 jobs processed per second. Processed reliably, in priority order, and with full visibility of every job.

### Test 2

For about a small improvement in performance, use mongo write_concern of 0.
This means Rocket Job does not wait for the MongoDB write operation to hit the journal (disk) before returning.

Update mongo.yml and add the following option under `:options`:

~~~yaml
    :w: 0
~~~

The following results were obtained when running 3 Rocket Job processes.

~~~
$ bundle exec rocketjob_perf -c 100000

Running: 15 workers, distributed across 3 processes
Waiting for workers to pause
Enqueuing jobs
Resuming workers
{
  :count => 100000,
  :duration => 96.9740002155304,
  :jobs_per_second => 1031
}
~~~

1,031 jobs processed per second. Processed reliably, in priority order, and with full visibility of every job.
