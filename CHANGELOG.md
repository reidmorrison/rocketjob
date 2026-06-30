# Change Log

All notable changes to this project will be documented in this file.
This project adheres to [Semantic Versioning](http://semver.org/).

## [6.4.0] Unreleased

### Fixes

- Fix a one-second (one poll interval) delay between regular jobs. After completing a
  non-batch job a worker waited the full `Config.max_poll_seconds` before polling again,
  so a full queue drained at one job per poll interval per worker instead of as fast as
  `#perform` allowed. Workers now poll again immediately when work was performed, and only
  wait the full interval when no job is found. A completed batch job is likewise no longer
  delayed. Regression introduced in v5.2.0 (the "Worker refactor").

### New features

- Support Mongoid 9.0 / 9.1 and ActiveRecord 8.1.

### Documentation

- Rewrite the documentation site: landing page, installation, Programmer's Guide, Batch
  Guide, Architecture and Internals (formerly "Advanced"), Included Jobs, Dirmon, and
  Mission Control (Web UI) pages, plus a new Upgrading guide and a rewritten README.
- Add `CLAUDE.md` and expand `CONTRIBUTING.md` with an architecture guide.

### Internal

- Enforce RuboCop in the default Rake task and CI, and apply autocorrections.
- Substantially expand test coverage across the worker pool, supervisor, subscribers,
  events, batch categories, batch IO, sliced input queries, Dirmon, and built-in jobs.
- Remove the unused `RactorWorker` placeholder.

## [6.3.2] 2026-01-24

- Release database connections back to the pool for Rails 7.2.

## [6.3.1] 2023-11-10

- Fix the spelling of a `priority` reference.

## [6.3.0] 2023-11-08

- Support Rails 7.1.
- Add a default priority of 30 for `CopyFileJob`.
- Rails 7: do not convert keys when calling `deep_symbolize_keys` on BSON.
- Fix a JDBC connection-closed issue.

## [6.2.0] 2023-07-31

- Support newer Mongoid versions and MongoDB 6.
- Refine retry delays.
- Fix `DirmonJob`.
- CI and documentation updates.

## [6.1.1] 2022-04-27

- Ruby 3.1 fixes.
- Update Appraisals.

## [6.1.0] 2021-11-04

- When a Dirmon entry raises an exception, move it to the failed state.

## [6.0.3] 2021-11-04

- Packaging fix release.

## [6.0.2] 2021-10-25

- Support Secret Config events.
- Initialize categories when accessed before initialization is complete.
- First cut of documentation for events in Rocket Job.

## [6.0.1] 2021-09-24

- Support Semantic Logger v5.
- Strip non-UTF-8 characters from exception messages.

## [6.0.0] 2021-08-25

### Breaking changes

- Batch input and output are now organized into first-class **Categories**
  (`RocketJob::Category::Input` / `Output`), each with its own serializer, file format,
  and slice collection, defined with a DSL (`input_category` / `output_category`).
  The legacy batch fields (`encrypt`, `compress`, `slice_size`, `collect_output`,
  `collect_nil_output`) and the standalone Tabular plugin attributes are migrated into
  categories; `collect_output` moved from regular jobs into batch jobs. See the v6 batch
  migration notes.
- Remove the deprecated Tabular plugin in favour of categories; Tabular rendering is now
  applied per output category after each `perform`. The Tabular plugins became an optional
  require.
- Remove the `Restart` plugin. `DirmonJob` is now a scheduled (cron) job rather than a
  restartable one.
- Switch batch categories to embedded Mongoid documents and migrate from BSON `Symbol`
  to `Mongoid::StringifiedSymbol`.
- Require Mongoid 7.1 or above.

### New features

- Support Ruby 3 (and add TruffleRuby to CI); initial support for Mongoid 7.3 / Rails 6.1.
- Compression is now used by default in batch jobs.
- Add Encrypted BZip2 output slices and support headers with binary output formats.
- `ThrottleDependentJobs` plugin to throttle jobs that depend on other jobs.
- Add `slice_batch_size` to upload small slices, and a single batch `upload` method.
- Handle very long file uploads by returning the database connection to the pool during
  upload; add an index to speed up the web UI.
- Make on-demand job attributes editable in Mission Control; add output-category helper
  methods for on-demand batch jobs.
- Support input and output categories in `DirmonEntry` and `UploadFileJob`; resume batch
  slices.

### Fixes

- Fix #22: the relation re-encryption job prevented non-Rails startup.
- Serialize `IOStreams::Path` as a string in YAML and Mongo.

### Internal

- Separate the thread worker from the base inline worker.
- Migrate CI to GitHub Actions.

## [5.4.1] 2020-12-09

- Fix batch jobs throttle overwriting the group job throttle.

## [5.4.0] 2020-12-08

- Support job throttling by named groups.
- Support multi-stream BZip2 format.
- Ruby 2.4 is no longer supported.

## [5.3.3] 2020-07-16

- Support fixed-width tabular input and output file formats.
- Fail a job when an exception is raised during `after_batch`, even when the job is invalid.
- Make the kill event take workers down hard sooner.
- Fix the cron timezone parser.
- Remove Mongoid deprecation warnings.

## [5.3.0] 2020-06-14

- Throttle batch job workers when outside of processing windows.
- Switch to `amazing_print`.
- Add contributing docs.

## [5.2.0] 2020-04-30

- Refactor throttles to be shared across regular and batch jobs, honouring inheritance.
- Allow a throttled batch job to be interrupted; reset the slice record number on retry.
- Drop Mongoid 5; support Mongoid 7.1 and the Mongo Ruby Driver v2.11.
- Worker refactor.
  - Note: this release introduced a one-poll-interval delay between regular jobs that was
    fixed in 6.4.0.

## [5.1.1] 2020-02-25

- Put the relational job under the correct namespace.

## [5.1.0] 2020-02-24

- Open source the Enterprise features: directly integrate encryption and compression of
  slices.
- Fix `pausable?` for regular jobs.

## [5.0.0] 2020-01-15

### Breaking changes

- Upgrade to IOStreams v1.
- New command-line arguments to start and stop servers.
- Refactor configuration; support Railtie configuration.

### New features

- Add a `CopyFileJob` to copy from any source to any destination using IOStreams, with more
  user-editable attributes.
- Add `OnDemandBatchTabularJob` and apply tabular encoding settings.
- Read from primary when critical.

### Fixes

- Fix `pausable` for regular jobs.
- Fix the filter after the re-check period.

## [4.2.0] 2019-08-19

- Clean up the input collection when an upload raises an exception.

## [4.1.1] 2019-07-01

- Allow `UploadFileJob` to take S3 URLs.
- Move batch index creation into the input writer class and avoid using `_type` in slice
  queries.
- Log the shutdown message at info level.

## [4.1.0] 2019-02-08

### New features

- Introduce a **Supervisor** to handle server and worker management, breaking the server
  code into smaller parts and a separate worker pool.
- Add publish/subscribe for immediate event notifications, including an event to kill
  servers or specific workers and the ability to subscribe to all events.
- Speed up shutdown by using an event semaphore.

## [4.0.0] 2018-11-13

### Breaking changes

- **Open source Rocket Job Pro** as the batch (`RocketJob::Batch`) feature set.

### New features

- Add Tabular support: input mode and type, multiple output categories, and carrying the
  header in the job.
- Add a `LowerPriority` plugin and a generalized on-demand job.
- `DirmonJob` now uses `UploadFileJob` to kick off jobs, setting the original file name.
- Support additional command-line filters.
- Log statistics as part of the completed and failed log messages when present.

## [3.4.3] 2017-09-18

- Fix housekeeping to use `completed_at` instead of `created_at`.

## [3.4.2] 2017-08-02

- Persist cron schedule clearance.

## [3.4.1] 2017-07-24

- Add `Job#sleeping?`.
- Add a missing `optparse` require.

## [3.4.0] 2017-07-13

- Allow cron jobs to fail and support adhoc runs.

## [3.3.4] 2017-06-29

- Allow a job to see when it will run next; recalculate `run_at` whenever `cron_schedule`
  changes.

## [3.3.3] 2017-06-13

- Rename the `#perform` metric name.

## [3.3.2] 2017-06-01

- Fix the retry plugin and the logger warning that occurred on restart.

## [3.3.1] 2017-05-09

- By default, jobs are not pausable.
- Exclude parent classes from the throttle count.
- Expose the Transaction plugin.

## [3.3.0] 2017-04-19

- Add a database Transaction plugin.
- Automatically clean up zombie workers.
- Use class attributes for the whitelist and archive directory variables.

## [3.2.1] 2017-04-06

- Add a missing require for the CLI.
- Rails (ActiveModel) 5.1 tests.

## [3.2.0] 2017-04-05

- Switch to named tags for job id and Dirmon entry id.
- Refactor restart to use a whitelist of attributes.
- Update the ActiveJob adapter for Rocket Job v3.

## [3.1.0] 2017-03-22

- Implement a job throttling framework (`throttle_filter_id`, `undefine_throttle`).
- Upgrade to AASM 4.12.

## [3.0.5] 2017-03-16

- Fix and rename `throttle_max_workers`.
- Fix intermittent test failures.

## [3.0.4] 2017-03-14

- Handle a nil `worker_name` from zombie workers.
- Use Appraisal to manage gemfiles.

## [3.0.3] 2017-03-02

- Handle a nil `worker_name`.

## [3.0.2] 2017-02-20

- Retry on restart so singletons can be removed from disk.
- Fix `ActiveWorker.requeue_zombies`.

## [3.0.1] 2017-02-03

- Also eager load the built-in jobs.

## [3.0.0] 2017-01-25

### Breaking changes

- **Switch from MongoMapper to Mongoid.** Jobs are now Mongoid documents.
- Separate `Worker` and `Server` into distinct classes and track jobs at the worker level,
  not just the server.
- Remove job arguments.

### New features

- Add `rocket_job_active_workers` and allow `ActiveWorker` to select on a server name.
- Limit which job classes a specific server can run; configurable `max_workers`.
- More configuration options at the command line.

## [2.1.3] 2016-08-01

- Replace `RESTART_EXCLUDES` with the class variable `rocket_job_restart_excludes`.

## [2.1.2] 2016-07-29

- Add `active_model/serializers/xml` as a dependency for ActiveModel v5.
- Change the hard-down log message level to warn.

## [2.1.1] 2016-07-13

- Add an ActiveJob adapter.
- Add a `Retry` plugin to automatically retry a job on failure.
- Add a housekeeping job and make `cron_schedule` editable in Mission Control.
- Only save changes to prevent overwriting changes made by other processes.

## [2.0.0] 2016-02-27

### Breaking changes

- Rename "Concerns" to **Plugins** and move job behaviour into plugins.
- Switch to Rails 3/4-style callbacks (`before_perform`, `after_perform`); deprecate the old
  inheritance-based callback mechanism. Support a single `perform` method and remove the
  `perform_method` attribute and backward-compatibility code.

### New features

- Add cron scheduling, processing windows, and a customized AASM that supports child classes
  changing the state machine.
- Add counts by state for Mission Control (jobs, workers, Dirmon entries).
- Allow restartable jobs to be destroyed and scheduled jobs to be paused.

## [1.3.0] 2015-09-25

- Allow a `before_perform` to fail a job; add `RocketJob::Job#work_now` to run a job inline.
- Add `Job.rocket_job_properties` to specify which properties are visible in Mission Control.
- Remove deprecated `sync_attr`.

## [1.2.1] 2015-09-15

- Make Dirmon entry file-name pattern matching case-insensitive.
- Fix `DirmonEntry` when the archive path does not exist.

## [1.2.0] 2015-09-10

- Support standalone configuration and apply defaults every time a job is created.
- Validate a job before processing during `#perform_now`.
- Fix Rails detection.

## [1.1.3] 2015-09-02

- Switch to Minitest specs.

## [1.1.2] 2015-08-27

- Fix worker zombie detection: only running workers can be zombies.
- Validate `DirmonEntry#perform_method` without raising an error.

## [1.1.1] 2015-08-25

- Allow `#fail` to take worker name and exception arguments.

## [1.1.0] 2015-08-20

- Major Dirmon refactor; add a job `Singleton` plugin that jobs can mix in.
- Add a requeue event so a dead worker's running jobs are re-queued, with callbacks for when
  a job is requeued after a worker dies.

## [1.0.0] 2015-07-30

- Add validations and a `name` to `DirmonEntry`.

## [0.9.1] 2015-07-22

- Make `duration` available for use in Mission Control.

## [0.9.0] 2015-07-21

- Rename `Server` to `Worker` and improve `#status`.

## [0.8.0] 2015-07-20

- Add `DirmonJob` to monitor directories for new files and start a job for each
  corresponding file.

## [0.7.0] 2015-07-13

- Initial public release of `rocketjob` (renamed from `rocket_job`).
- MongoDB-backed batch processing: stream records into a job and results out via slices,
  with compression and encryption for the streaming APIs (zip, gzip, encrypted, and
  user-definable formats).
- `bin/rocket_job` command-line interface for running servers.
- Pause, resume, and abort job state transitions; run jobs in the future with `run_at`.
- Separate input and output collections, reusable across multi-file patterns.
