# v7 / v8 compatibility harness

This harness checks that the pre-schema options of a batch job's input and output categories behave on this
repository as they did on the released rocketjob 7.0.0 with IOStreams 2.1.0. Those options are an input category's
`allowed_columns`, `required_columns`, `skip_unknown` and `header_cleanser`, the `columns` of a headerless file or of
an output category, and `format_options`. No scenario uses `schema:`.

It runs the same scenarios under two bundles and compares what happened, scenario by scenario:

- `v7/Gemfile`: rocketjob 7.0.0 and iostreams 2.1.0 from rubygems.org.
- `v8/Gemfile`: this repository, as it is checked out, with IOStreams from GitHub main, as the repository's own
  Gemfile and CI use it.

For each scenario it defines a batch job class, uploads a small file, processes the job with `#perform_now`, and
downloads its output. It records the upload's return value and `record_count`, the input category's `columns`, each
record exactly as `#perform` received it, the downloaded text, every exception with the step that raised it, and every
deprecation warning with the file and line that it names. The scenarios are in `scenarios/`:

- 1 to 8 (ids `A`): CSV with each column option, also in the `:array` and `:hash` upload modes, whose ids end in
  `__mode_array`, `__mode_hash`, `__stream_array` and `__stream_hash`.
- 9 (ids `C`): PSV, JSON, fixed width with `format_options`, and `format: :auto`.
- 10: output categories, `nils`, and `Batch::Result`.
- 11 (ids `E`): jobs built with `from_properties`, as a Dirmon entry or an `UploadFileJob` builds them, plus the
  property checks of `.property_errors`, `DirmonEntry` and `UploadFileJob`.
- Ids `F`: jobs that are saved and reloaded before they are processed, as a server's worker loads them.
- Ids `G`: records written to the block of `upload`.
- Ids `H`: some of the scenarios above again with `IOStreams.enforce_column_restrictions = false`, the documented
  way to keep the v7 column restrictions.
- Ids `I`: options supplied to `upload` itself, such as `stream_mode:` and `format_options:`.
- 12: jobs that v7 saves without processing, then processed by v7 and by v8, with `#perform_now` and the way a
  server's worker processes them. Also a job that v8 loads and writes back whole, then v7 processes, as during a
  rolling upgrade.

It is run by hand, like `test/performance/batch_benchmark.rb`. None of its files ends in `_test.rb`, so `rake test`
never collects it and CI never runs it.

## Running it

It needs MongoDB on 127.0.0.1:27017 (`docker compose up -d`), network access for the first `bundle install` of each
bundle, and Ruby 3.3 or later. From the root of the repository, run it directly, not under `bundle exec`:

~~~bash
test/compat/run_all.sh
~~~

The script installs both bundles when needed and runs every step. It writes the results to `tmp/compat` at the root
of the repository, which `.gitignore` ignores. Set `COMPAT_RESULTS` to write them somewhere else:

~~~bash
COMPAT_RESULTS=/tmp/compat-main test/compat/run_all.sh
~~~

The harness uses the databases `rocketjob_compat_v7`, `rocketjob_compat_v8` and `rocketjob_compat_shared`, never the
test databases, and drops them when it finishes, also when a step fails. Pass `--keep` to keep them, with the jobs
of the matrix in the first two and those of scenario 12 in the last:

~~~bash
test/compat/run_all.sh --keep
~~~

To run one step under one version, such as some of the scenarios while working on them:

~~~bash
BUNDLE_GEMFILE=test/compat/v8/Gemfile bundle exec ruby test/compat/run.rb matrix '^C0'
BUNDLE_GEMFILE=test/compat/v8/Gemfile bundle exec ruby test/compat/run.rb drop
~~~

A matrix run of some of the scenarios replaces the results of a run of all of them. The other steps are `checks`,
`persist-create`, `persist-process COPY`, `persist-worker COPY` and `persist-touch COPY`, in the order that
`run_all.sh` runs them, see `support/command.rb`.

The lock files of the bundles are not committed, so the first `bundle install` takes the latest IOStreams main, as CI
does. To take a newer one later:

~~~bash
BUNDLE_GEMFILE=test/compat/v8/Gemfile bundle update iostreams
~~~

## Comparing the results

`run_all.sh` finishes by writing every comparison to `tmp/compat/compare-*.txt`, and prints how many scenarios are the
same and how many differ. Each difference shows the v7 value and then the v8 value:

- `compare-matrix.txt`: scenarios 1 to 11.
- `compare-persist.txt`: scenario 12 with `#perform_now`.
- `compare-persist-worker.txt`: scenario 12 the way a server's worker processes it.
- `compare-persist-mixed.txt`: scenario 12 when v8 wrote the job back before v7 processed it. It starts with how
  many jobs v8 wrote, how many of those it changed, and each job that v8 could not load or save, which v7 then
  processed as v7 saved it.
- `compare-triage.txt`: the CSV scenarios of the `:array` and `:hash` modes that differ, by whether v7 raised. v7
  raised for many of them, so those differences are fixes.
- `compare-checks.txt`: the property checks.
- `compare-warnings.txt`: the deprecation warnings of v8, by scenario, with the line that each one names.

To print one comparison, or compare the v8 results of two runs, such as of two commits, labelled by their results
directories:

~~~bash
ruby test/compat/compare.rb matrix
COMPAT_RESULTS=/tmp/compat-branch ruby test/compat/compare.rb versus /tmp/compat-main
~~~

The JSON files in `tmp/compat` hold the full result of every scenario, including its definition and the backtrace of
each error.

## What it does not cover

- The `:bz2` and `:encrypted_bz2` output serializers, since neither bundle includes `bzip2-ffi`.
- Uploads of a `Mongoid::Criteria`, an `ActiveRecord::Relation` or an integer range, which do not use the column
  options.
- A schema, which v7 does not have.
