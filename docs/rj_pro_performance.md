---
layout: default
---
## Rocket Job Pro Performance Test

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
bundle exec rocketjob_pro_perf -c 1000
~~~

Full test:

~~~
bundle exec rocketjob_pro_perf
~~~

### Test 1

The following results were obtained when running 3 Rocket Job processes.

~~~
Already running: 15 workers, distributed across 3 processes
Loading job with 10000000 records/lines
Waiting for job to complete
{
  :count=>10000000,
  :duration=>18.731,
  :records_per_second=>533874.326,
  :workers=>15,
  :worker_processes=>3
}
~~~

533,874 records/lines processed per second. Processed reliably, in priority order, and with full visibility of every job.

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

Already running: 15 workers, distributed across 3 processes
Loading job with 10000000 records/lines
Waiting for job to complete
{
  :count=>10000000,
  :duration=>17.832,
  :records_per_second=>560789.592,
  :workers=>15,
  :worker_processes=>3
}
~~~

560,789 records/lines processed per second. Processed reliably, in priority order, and with full visibility of every job.

By increasing the `slice_size` further, results in even higher processing rates.

Enabling or disabling compression and/or encryption does not appear to have a significant impact on processing times.
