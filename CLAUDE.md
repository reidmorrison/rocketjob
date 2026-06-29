# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`rocketjob` is a Ruby gem: a distributed, MongoDB-backed batch processing system. Jobs are Mongoid documents persisted to MongoDB; servers pull queued jobs and run them across worker threads. There is no Rails app here, only the library plus its test suite. The web UI (Mission Control) and Tabular plugins live in separate gems.

The primary public interface is `RocketJob::Job`; capabilities are added by mixing in modules such as `RocketJob::Batch`. Treat that surface (subclassing `Job`, opt-in mixins, typed fields, `#perform`, queuing/downloading, documented state transitions) as the stable contract; everything under `Plugins`, `Sliced`, and the runtime classes is internal.

## Why this design

Context worth knowing before changing core behavior:

- **Two tiers of jobs.** Simple jobs (`RocketJob::Job`) are conventional background jobs like other frameworks offer. Batch jobs (`include RocketJob::Batch`) are the real point of Rocket Job: a single job's input is uploaded into a dynamically created MongoDB collection, split into slices, and processed concurrently across thousands of workers (often Docker containers). Output is written back to MongoDB the same way.
- **Why MongoDB.** Its atomic `find_and_modify` lets thousands of nodes claim work without colliding, and it spills from memory to disk, which is essential for very large files. Rocket Job was built because Sidekiq/Redis could not scale this way (Redis was single-threaded and could not overflow to disk). Also supports AWS DocumentDB.
- **Why Mongoid.** Jobs are documents with real, typed, validated fields, not an untyped hash of arguments.
- **Backward compatibility is a priority.** Only break it in a major release, ideally with a deprecation path first. Most forced changes come from breaking changes in MongoDB/Mongoid. When adding persisted fields to a plugin, give them defaults so existing jobs in the database still load.

A class diagram of the core relationships is in [CONTRIBUTING.md](CONTRIBUTING.md) under "Architecture".

## Commands

Tests require a running MongoDB on `127.0.0.1:27017` (see `docker-compose.yml`: `docker compose up -d`). Test config is `test/config/mongoid.yml` and the suite drops/recreates collections on load.

- Run full suite (against current `Gemfile`): `bundle exec rake test`
- Run one test file: `bundle exec ruby -Itest -Ilib test/job_test.rb`
- Run one test by name: `bundle exec ruby -Itest -Ilib test/job_test.rb -n /pattern/`
- Lint: `bundle exec rubocop` (config in `.rubocop.yml`)
- Test logs go to `test.log` (not stdout); use it to debug failures.

`rake` with no args runs the full matrix via Appraisal, not a single test run. Don't use bare `rake` for quick iteration.

### Multi-version testing (Appraisal)

CI runs against multiple Mongoid/Rails/Ruby combinations defined in `Appraisals` (Mongoid 8.1, 9.0, 9.1) with generated gemfiles in `gemfiles/`. To target one combination:

- `BUNDLE_GEMFILE=gemfiles/mongoid_9.1.gemfile bundle exec rake test`
- Regenerate gemfiles after editing `Appraisals`: `bundle exec appraisal install`

### Test conventions and gotchas

The suite is Minitest with `minitest/spec` `describe`/`it` blocks nested inside `class FooTest < Minitest::Test`. Heavy use of `Minitest::Mock`, `.stub`, and `minitest-stub_any_instance`. Useful things learned writing tests:

- **Coverage.** SimpleCov runs automatically (started in `test_helper.rb`). After a run, overall % prints to stdout and `coverage/.resultset.json` holds per-file line hits — parse it to find the least-covered files and exact missing line numbers. `coverage/index.html` is the browsable report.
- **Shared class-level state must be reset between tests.** `Supervisor` keeps `@shutdown`/`@event` (`Concurrent::Event`) as class instance vars; `Event` keeps a class-level `@subscribers` map; `Subscriber` has `@test_mode`. Reset these in `before`/`after` or tests leak into each other. See `test/supervisor_test.rb` / `test/event_test.rb` for the reset helpers.
- **Autoload ordering.** Constants are `autoload`ed in `lib/rocketjob.rb`. Some files trigger circular loads when referenced first in isolation — e.g. referencing `RocketJob::WorkerPool` before `RocketJob::Supervisor` fails because `worker_pool.rb` requires `supervisor/shutdown`. Fix by `require`ing the dependency (e.g. `require "rocket_job/supervisor"`) at the top of the test.
- **Exercising persisted/legacy documents.** `Mongoid::Factory.from_db(JobClass, doc_hash)` instantiates with `new_record? == false` and fires `after_initialize` — this is how to trigger the v5→v6 batch category migration (`Batch::Categories#rocketjob_categories_migrate`) without a real legacy DB. A plain in-memory hash can hold Ruby Symbols that `test_helper.rb` would otherwise reject on BSON serialization.
- **State without the state machine.** `Job.new(state: :completed)` sets the field directly so predicates like `completed?` work without driving an `aasm` transition. Batch sub-states are similar: `job.start; job.sub_state = :processing`.
- **Driving real worker threads.** `ThreadWorker.new` immediately spawns a thread running `#run`; if you `kill` it before it enters `run`, the `Shutdown` exception is unhandled and `join` re-raises it — let the thread start first. A plain `Worker` is the inline/no-op strategy and is trivially testable.
- **ActiveRecord in tests.** `upload_arel`/transaction tests use a sqlite DB via `test/config/database.yml` + an inline `ActiveRecord::Schema.define`. See `test/plugins/transaction_test.rb` and `test/sliced/input_query_test.rb`.
- **Misc.** `DirmonEntry#pattern` is unique-validated (use distinct patterns per fixture). `Batch::Model#worker_count` caches for one second. `Category#file_name` returns an `IOStreams::Path`, not the raw string. The `job_has_properties` category-validation branch (in `UploadFileJob`/`DirmonEntry`) is only reachable for non-batch job classes, since batch jobs define the `input_categories=`/`output_categories=` setters that short-circuit it.

## Architecture

### Jobs are composed from plugin modules

`RocketJob::Job` ([lib/rocket_job/job.rb](lib/rocket_job/job.rb)) is deliberately near-empty: it `include`s a stack of plugin modules from `Plugins::Job::*` (Model, Persistence, Callbacks, Logger, StateMachine, Worker, Throttle, ...). User jobs subclass `RocketJob::Job` and implement `#perform`. This composition pattern is central: behavior lives in `lib/rocket_job/plugins/`, not in the `Job` class itself. Optional plugins (`Cron`, `Singleton`, `Retry`, `ProcessingWindow`, `ThrottleDependentJobs`) are mixed in per-job by the user.

State transitions (queued → running → completed/failed/aborted/paused) are driven by the `aasm` gem via the StateMachine plugins.

### Batch jobs

Including `RocketJob::Batch` ([lib/rocket_job/batch.rb](lib/rocket_job/batch.rb)) turns a job into a parallel one: input is split into *slices* processed concurrently by many workers. Slices are stored in a **separate Mongo collection/client** (`rocketjob_slices`, distinct from the `rocketjob` client) — see `lib/rocket_job/sliced/`. Input/output are organized by **categories** (`RocketJob::Category::Input`/`Output`, configured via `input_category`/`output_category`), each with its own serializer (plain, compressed, encrypted, bzip2), file format, and collection. `lib/rocket_job/batch/io.rb` handles `upload`/`download`.

### Runtime: Supervisor → WorkerPool → Workers

- `Supervisor` ([lib/rocket_job/supervisor.rb](lib/rocket_job/supervisor.rb)) is the process entry point (`bin/rocketjob` → `RocketJob::CLI`). It registers a `Server` document, manages the `WorkerPool`, handles signals, and runs the event/subscriber listeners.
- `Server` is a Mongoid document representing a running process; `Worker` represents one thread. `ThreadWorker` and `RactorWorker` are the execution strategies.
- Cross-process coordination (shutdown, pause, log-level changes) uses a pub/sub mechanism over MongoDB: `RocketJob::Event` + `Subscriber`/`Subscribers::*`. There is no separate message broker.

### Config and persistence

- `RocketJob::Config.load!(env, mongoid_path, symmetric_encryption_path)` bootstraps Mongoid and Symmetric Encryption (see `test/test_helper.rb` for the canonical call).
- Two Mongo clients are required in `mongoid.yml`: `rocketjob` (jobs) and `rocketjob_slices` (batch slices).
- `lib/rocket_job/extensions/` monkey-patches Mongoid/Mongo/Psych. Notably, **BSON Symbols are deliberately unsupported** (Mongoid/MongoDB deprecated them); `test_helper.rb` raises if a Symbol is serialized. Use the `StringifiedSymbol` type / strings for field values.

### Built-in jobs

`lib/rocket_job/jobs/` ships ready-to-use jobs: `DirmonJob` (directory monitor that enqueues jobs for arriving files, paired with `DirmonEntry`), `HousekeepingJob`, `OnDemandJob`/`OnDemandBatchJob` (run arbitrary Ruby), `UploadFileJob`, `CopyFileJob`, `ConversionJob`. The ActiveJob adapter is `lib/rocket_job/extensions/rocket_job_adapter.rb`.

## Documentation

User-facing guides are Jekyll markdown in `docs/` (published to rocketjob.io). Edit these for behavior/usage doc changes; serve locally with `cd docs && bundle update && jekyll serve`.
