---
layout: default
---

## Directory Monitoring

A common task with many batch processing systems is to look for the appearance of
new files and queue jobs to process them. `DirmonJob` is a job designed to do
this task.

`DirmonJob` runs every 5 minutes by default, looking for new files that have appeared
based on configured entries called `DirmonEntry`. These entries can be managed
programmatically, or via [Rocket Job Mission Control][1], the web management interface for [Rocket Job][0].

Example, creating a `DirmonEntry`

~~~ruby
entry = RocketJob::DirmonEntry.create!(
  pattern:           '/path_to_monitor/*',
  job_class_name:    'MyFileProcessJob',
  archive_directory: '/exports/archive'
)
~~~

When a Dirmon entry is created it is initially `disabled` and needs to be enabled before
DirmonJob will start processing it:

~~~ruby
entry.enable!
~~~

Active dirmon entries can also be disabled:

~~~ruby
entry.disable!
~~~

The attributes of DirmonEntry:

* `pattern` <String>
    * Wildcard path to search for files in.
      For details on valid path values, see: http://ruby-doc.org/core-2.2.2/Dir.html#method-c-glob
    * Examples:
        * input_files/process1/*.csv*
        * input_files/process2/**/*
* `job_class_name` <String>
    * Name of the job to start
* `arguments` <Array>
    * Any user supplied arguments for the method invocation
      All keys must be UTF-8 strings. The values can be any valid BSON type:
        * Integer
        * Float
        * Time    (UTC)
        * String  (UTF-8)
        * Array
        * Hash
        * True
        * False
        * Symbol
        * nil
        * Regular Expression
        * _Note_: Date is not supported, convert it to a UTC time

* `properties` <Hash>
    * Any job properties to set.
        * Example, override the default job priority:

~~~ruby
{ priority: 45 }
~~~

* `archive_directory`
    * Archive directory to move the file to before the job is started. It is important to
      move the file before it is processed so that it is not picked up again for processing.
      If no archive_directory is supplied the file will be moved to a folder called '_archive'
      in the same folder as the file itself.
      If the `path` above is a relative path the relative path structure will be
      maintained when the file is moved to the archive path.

### Starting the directory monitor

The directory monitor job only needs to be started once per installation by running
the following code:

~~~ruby
RocketJob::Jobs::DirmonJob.create!
~~~

The polling interval to check for new files can be modified when starting the job
for the first time by adding:

~~~ruby
RocketJob::Jobs::DirmonJob.create!(check_seconds: 180)
~~~

The default priority for `DirmonJob` is 40, to increase it's priority:

~~~ruby
RocketJob::Jobs::DirmonJob.create!(
  check_seconds: 180,
  priority:      25
)
~~~

Once `DirmonJob` has been started it's priority and check interval can be
changed at any time as follows:

~~~ruby
RocketJob::Jobs::DirmonJob.first.update_attributes(
  check_seconds: 180,
  priority:      20
)
~~~

### High Availability

The `DirmonJob` will automatically re-schedule a new instance of itself to run in
the future after it completes each scan/run. If successful the current job instance
will destroy itself.

In this way it avoids having a single Directory Monitor process that constantly
sits there monitoring folders for changes. More importantly it avoids a _single
point of failure_ that is typical for earlier directory monitoring solutions.
Every time `DirmonJob` runs and scans the paths for new files it could be running
on a different worker. If any worker is removed or shutdown it will not stop
`DirmonJob` since it will just run on another worker instance.

There can only be one `DirmonJob` instance `queued` or `running` at a time.

If an exception occurs while running `DirmonJob`, a failed job instance will remain
in the job list for problem determination. The failed job cannot be restarted and
should be destroyed when no longer needed.

### [Next: Support ==>](support.html)

[0]: http://rocketjob.io
[1]: https://github.com/rocketjob/rocketjob_mission_control
[2]: http://rocketjob.github.io/semantic_logger
[3]: https://github.com/rocketjob/rocketjob
