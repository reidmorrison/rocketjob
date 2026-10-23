---
layout: default
title: Upgrading Rocket Job
description: >-
  The upgrade steps that need code or data changes when moving between
  versions, for v8, v7.1, v6 and v3, and why to upgrade one version at a time.
---

**Contents**

* TOC
{:toc}

Release notes for every version are published in the
[GitHub Releases](https://github.com/reidmorrison/rocketjob/releases). This page collects the
upgrade steps that need code or data changes when moving between versions.

## Upgrade one version at a time

Upgrade through each version in turn, such as from v7.0 to v7.1, and then to v8, rather than from
v7.0 straight to v8. After each upgrade, fix every deprecation warning that it reports before you
upgrade to the next version:

1. Upgrade to the next version, following its section below.
2. Run your tests with Ruby's deprecation warnings on, see
   [Find the deprecated options that you use](#find-the-deprecated-options-that-you-use), and
   change each line that a warning names, until none are left.
3. Change the saved documents that still hold a deprecated option, such as Dirmon entries, scheduled
   jobs and `UploadFileJob`s, since reading one back reports no warning, see
   [Propose the schema of each category](#propose-the-schema-of-each-category).
4. Deploy, stopping every server on the old version before any server starts on the new one, see
   [Deploying a new version](deployment.html#deploying-a-new-version), and only then upgrade to the
   next version.

A minor release, such as v7.1, adds what replaces the options that the next major release removes,
and deprecates them, so that each change can be made, and tested, while the old option still works.
The next major release, such as v8, then removes what was deprecated, so code that still uses it
stops working.

## Upgrading to v8

Upgrade to v7.1 first, and fix every deprecation warning that it reports, see
[Upgrading to v7.1](#upgrading-to-v71). v7.1 deprecates the category options that a schema replaces,
which v8 removes, and runs on IOStreams 2.2 and Ruby 3.2, so those changes can be made, and tested,
before v8 changes Ruby, IOStreams and how files are read.

Rocket Job v8 requires IOStreams 3.0, and so Ruby 3.3 or later, which IOStreams 3.0 requires. On
JRuby that is JRuby 10.0 or later. Upgrade Ruby before upgrading Rocket Job.

Upgrade every server that runs workers at the same time, rather than running v7 and v8 workers
together. A v7 worker reads the jobs that v8 saves, but ignores the options that v8 adds, such as a
category's `schema` or `encoding`. A file that v8 uploads into an input category with a `format`, such
as CSV, is stored in slices that a v7 worker cannot read, so it fails each one, and they can be
retried once every worker runs v8.

### The deprecated category options are removed

v8 removes the category options that v7.1 deprecates, since a category's `schema` replaces them.
Replace each one while v7.1 still reads it, as its upgrade steps describe:

* A category's `format_options`, the layout of a fixed width file, see
  [Replace format_options with a schema](#replace-format_options-with-a-schema). A category with
  `format: :fixed` needs a schema, which gives the width of each field, so without one IOStreams 3.0
  raises `ArgumentError` when the category reads or writes a record.
* An input category's `allowed_columns`, `required_columns`, `skip_unknown` and `header_cleanser`,
  the `columns` of a file without a header row, and an output category's `columns`, see
  [Replace the column options with a schema](#replace-the-column-options-with-a-schema). The same
  options supplied to `upload`, such as `allowed_columns:` or `cleanse_header:`, raise
  `ArgumentError`. A `:csv`, `:psv` or `:fixed` output category needs a schema, whose fields are the
  columns that it writes, in order.
* An input category's `mode: :array`, and the `stream_mode: :array` of `upload`, see
  [Replace the :array upload mode](#replace-the-array-upload-mode), where v8 reads `:hash` as
  `validate_rows: true`, see
  [Replace the :hash mode with validate_rows](#replace-the-hash-mode-with-validate_rows). A file that v7
  uploaded in the `:array` mode, whose slices hold an Array for each row, is still processed.

Code or a saved document that still sets one fails, naming the option, rather than reading or
writing the records of the category as though it were not set:

* A job class that defines a category with one raises `ArgumentError` when it is loaded.
* A Dirmon entry or an `UploadFileJob` whose properties hold one fails validation when it is saved,
  and one that was saved before raises `ArgumentError` when it builds its job, such as when Dirmon
  finds a file.
* A job saved before v8 whose category holds one, such as a scheduled job, raises `ArgumentError`
  when that category reads or writes its records, such as when its file is uploaded, or a worker
  processes one of its slices. For the `:array` mode only an upload raises, since the Arrays that v7
  uploaded are still processed, and the next run of a scheduled job with it is still created.
* An input category's `columns` are not set by v8, since each slice of a file holds its header row.
  Uploading a file without a schema into a category saved with `columns`, such as those set for a
  file without a header row, raises `ArgumentError`, rather than reading the file by them. So does
  reading the records of a category saved with columns that reading them as a header row would
  change, such as columns that were not cleansed, see
  [Each slice holds the header row of its file](#each-slice-holds-the-header-row-of-its-file).

An option that is blank, or at its default, is ignored, such as a blank `format_options`, or
`skip_unknown: false` and `header_cleanser: :default`, which Rocket Job 7 saved with every input
category, and which Mission Control can save in the properties of a Dirmon entry. Any other value
fails, even where Rocket Job 7 did not apply it, such as `skip_unknown: true` without
`allowed_columns`.

v8 reports no deprecation warnings, and has no `RocketJob::SchemaProposal`, which v7.1 adds for the
move to v8. So find the deprecated options with v7.1, before upgrading: its deprecation warnings name
each line of code that uses one, see
[Find the deprecated options that you use](#find-the-deprecated-options-that-you-use), and
`RocketJob::SchemaProposal.report` lists each saved job, Dirmon entry and `UploadFileJob` that holds
one, with the schema that replaces it, see
[Propose the schema of each category](#propose-the-schema-of-each-category).

### A header row is cleansed as IOStreams 3.0 cleanses it

Without a schema, the columns of a header row are cleansed as IOStreams 3.0 cleanses them, which keeps
the letters that are not ASCII, and treats whitespace that is not ASCII, such as a no-break space, as a
space. So the column `Prénom` is `prénom`, where it was `prnom`, which changes the keys of the records
that `#perform` receives. With a schema, the keys of each record are the names of its fields, which
the columns are matched to whatever their case, spaces and punctuation.

### Each slice holds the header row of its file

v7 kept the header row that `upload` read from a file without a schema in the input category's
`columns`, and its workers read each line by it. v8 uploads every file in a `format`, such as CSV,
in slices that each hold the header row of the file, as it is in the file, and its format, as it
does with a schema, see [More than one file](batch.html#more-than-one-file). `#perform` receives the
same Hash for each line, so most jobs need no change, but:

* A second file with a header row can be uploaded into the same input category, in any mode, and its
  lines are read by its own header row. v7 stored the second file's header row as a record, and read
  its lines with the first file's columns.
* A file in a format is uploaded as its lines in every mode, see
  [Replace the :hash mode with validate_rows](#replace-the-hash-mode-with-validate_rows).
* The block of `upload` writes the lines of a file into a category with a format: its header row
  first, when the file has one, then its rows. Writing anything else raises `ArgumentError`, such as an
  Array of the values of each row of CSV, after the Array of its header row, or a Hash into a JSON
  category, which v7 read as it read a line. Write each row as a line of the format instead, such as
  `row.to_csv` or `hash.to_json`, or upload it into a category without a format, whose `#perform`
  receives it as it was written. The `:hash` and `:array` formats, whose rows are Ruby objects, and
  formats whose rows are not lines, such as Parquet, still upload each record as it is.
* The lines of a file in a format with a header row, such as CSV, that `upload_slice` uploads after
  `upload` uploaded a file are not read by its header row, which the category no longer keeps, so a
  worker raises `ArgumentError` for them. Write them to the block of `upload` instead, after the
  header row. Hashes, and the lines of a format without a header row, such as JSON, are still read.
* Options that read the lines of a file, such as `delimiter:`, raise `ArgumentError` for a category
  with a format, whose lines are read in it.
* A slice of an input category holds an `IOStreams::Slice` of rows, rather than an Array, for code
  that reads the records of a slice itself, such as Mission Control.
* The next run of a batch job that `RocketJob::Plugins::Cron` creates after the job uploaded its
  file, such as one with `cron_after_start: false`, whose next run is created when it completes or
  fails, reads the header row of its own upload. v7 copied the header row that the upload read into
  the next run, so each later run stored its file's header row as a record. A job saved by v7 does
  not record that its columns came from a file, so the upload of its next run raises `ArgumentError`
  rather than reading the file by them. Clear them once after upgrading, for each such scheduled job
  class, and again once the jobs of that class that were running when you upgraded have finished,
  since their next runs are copied from them:

  ~~~ruby
  MyScheduledJob.where(:state.in => %w[queued paused]).each do |job|
    job.input_categories.each do |category|
      category.columns = nil
    end
    job.save!
  end
  ~~~

### Replace the :hash mode with validate_rows

An input category's `validate_rows: true` replaces its `mode: :hash`, and the `validate_rows:` of
`upload` replaces its `stream_mode:`. Each line of a file in the category's format is parsed while the
file is uploaded, so that a file with a line that cannot be read is rejected, and nothing is
uploaded, before processing starts. The slices hold the lines, as they do without it, rather than the
Hashes that v7 uploaded, and `#perform` receives the same Hash for each line:

~~~ruby
# Before
input_category format: :csv, mode: :hash
job.upload("people.csv", stream_mode: :hash)

# After
input_category format: :csv, validate_rows: true
job.upload("people.csv", validate_rows: true)
~~~

* A category's `mode` is still read, so that a job class, a saved job, such as a scheduled job, and
  a Dirmon entry with it need not change: `mode: :hash` validates the rows of a file in a format, as
  `validate_rows: true` does, unless `upload` is given `validate_rows: false`. Without a format it has
  no effect, as in v7.0.
* `stream_mode:` raises `ArgumentError`, with any value, since `validate_rows:` replaces it.
* `stream_mode: :hash` read a file into a category without a format as Hashes, in the format of its
  file name. Set the category's `format: :auto` instead, which reads a file in the format of its file
  name, otherwise CSV, so that `#perform` receives the same Hashes, apart from the columns of a
  header row that IOStreams 3.0 cleanses differently, see
  [A header row is cleansed as IOStreams 3.0 cleanses it](#a-header-row-is-cleansed-as-iostreams-30-cleanses-it).
  `validate_rows: true` needs a format, and raises `ArgumentError` without one.
* A category's `validate_rows: false` is used in place of its `mode: :hash`, so that a job class can
  stop validating the rows of the files of saved jobs and Dirmon entries with it. Left unset, the
  `mode` decides.
* `validate_rows:` applies to a file, and the lines that the block of `upload` writes. A query or a
  range uploads values rather than rows, so `upload` raises `ArgumentError` for `validate_rows: true`
  with one, and the category's `validate_rows` does not apply to it.

### An Active Record query is streamed

`upload` reads an Active Record relation with IOStreams 3.0, as one query that the database
streams, rather than with `find_each`, which built a model for each row, see
[Active Record queries](batch.html#active-record-queries):

* The rows are uploaded in the order of the relation, and within its limit. v7 uploaded them in the
  order of their ids, so `User.order(created_at: :desc).limit(100)` uploaded the first 100 users by
  id, rather than the 100 most recent.
* Each column is read as `pluck` reads it, which is the value that the column holds, as its
  attribute casts it. A reader that the model overrides is not called, so
  `def name = super.upcase` no longer changes what is uploaded. Do what the reader did in
  `#perform` instead, or in the query.
* The query is read on a connection of its own, so it uploads only the rows that were committed.
  v7 also uploaded the rows that an open transaction of the caller wrote: upload them once that
  transaction commits. The pool of the model needs a connection free besides the one of the caller,
  for each thread that uploads at the same time, otherwise `upload` raises
  `ActiveRecord::ConnectionTimeoutError`, such as within a transaction, or in a job that includes
  `RocketJob::Plugins::Transaction`.
* The query stays open until every row is uploaded, where `find_each` ran a short query for each
  batch. For a very large table, a query held open for hours holds back vacuum on PostgreSQL and
  makes a change to the table, such as `ALTER TABLE`, wait for it: upload the batches of the
  relation instead, see below.
* It needs Active Record 7.2 or later, both for a relation and for its batches, and raises
  `ArgumentError` for an earlier version: upgrade Active Record, or write the records in a block of
  `upload`, see below.
* It needs a database whose driver streams a query: PostgreSQL,
  MySQL with `mysql2`, or SQLite with `sqlite3`. Any other raises `ArgumentError`, such as MySQL with
  `trilogy`, SQL Server, or SQLite on JRuby: upload the batches of the relation instead, selecting
  the columns to upload before `in_batches`, without which they raise `ArgumentError`:

  ~~~ruby
  # Before
  job.upload(User.where(country_code: "US"), columns: %i[user_name zip_code])

  # After
  job.upload(User.where(country_code: "US").select(:user_name, :zip_code).in_batches)
  ~~~
* A relation that loads associations with `includes`, `preload` or `eager_load` raises
  `ArgumentError`, since no models are built. Join their tables with `joins` instead.

### A paused Singleton job is active

A job that includes `RocketJob::Plugins::Singleton` is not valid while another job of its class is
running, queued, or now also paused. The check runs whenever such a job is saved, not only when it is
created, so a queued job saved by v7 alongside a paused one of the same class fails the next time it
is saved, such as when a server starts it. Before upgrading, check each such class, and when it has
more than one, abort or destroy all but one of them:

~~~ruby
active = MySingletonJob.where(:state.in => %w[running queued paused]).to_a
if active.size > 1
  active.each do |job|
    puts "#{job.id} #{job.state}"
  end
end
~~~

### Removed

These were deprecated or unused, and are removed in v8:

* `RocketJob::Plugins::Restart`, deprecated in v6. Use `RocketJob::Plugins::Cron`, see
  [Scheduled jobs](guide.html#scheduled-jobs).
* `RocketJob::LookupCollection`, which was not used by Rocket Job, and whose `upload` always raised
  `ArgumentError`.
* `#work_first_slice` of a batch job, deprecated in v6. In a `before_batch` callback, read the records
  of the first slice with `input.first` instead.
* The translation of batch jobs saved by v5 into v6 categories, when they are read. A job saved by
  v5, and never saved since by v6 or v7, cannot be read by v8: finish or destroy such jobs, or open
  and save them with v7, before upgrading.
* `upload_arel`, `upload_mongo_query`, `upload_integer_range` and
  `upload_integer_range_in_reverse_order` of a batch job, deprecated in v6. Call `upload` with the
  query or the range instead, with the columns to upload as `columns:`, see
  [Uploading input data](batch.html#uploading-input-data):

  ~~~ruby
  # Before
  job.upload_arel(User.where(country_code: "US"), :user_name, :zip_code)
  job.upload_mongo_query(User.where(state: "FL"), :zip_code)
  job.upload_integer_range(1, 1_000_000)
  job.upload_integer_range_in_reverse_order(1, 1_000_000)

  # After
  job.upload(User.where(country_code: "US"), columns: %i[user_name zip_code])
  job.upload(User.where(state: "FL"), columns: [:zip_code])
  job.upload(1..1_000_000)
  job.upload(1_000_000..1)
  ~~~

  `upload` does not take a block with a query. Where a block passed to `upload_arel` or
  `upload_mongo_query` returned the record to upload for each model or document, write the records
  in a block of `upload` instead:

  ~~~ruby
  # Before
  job.upload_arel(User.where(country_code: "US")) do |user|
    user.email.downcase
  end

  # After
  job.upload do |records|
    User.where(country_code: "US").find_each do |user|
      records << user.email.downcase
    end
  end
  ~~~

  A range
  is uploaded in the direction it is written, so where `upload_integer_range(first, last)` was called
  with bounds that it computed, which uploaded nothing when `last` was less than `first`, check for
  that before calling `upload(first..last)`, which uploads the range in reverse instead. A range that
  excludes its end, such as `1...100`, does not upload it. The
  `before_code` of an `OnDemandBatchJob` that calls one of them, as its documentation showed, raises
  `NoMethodError` when the job runs: change it to call `upload`, including in the jobs that are already
  saved, such as a scheduled one, which copies its `before_code` to its next run.
* `upload_file_name` and `upload_file_name=` of a batch job, deprecated in v6, which read and set the
  `file_name` of its input category. Use the input category instead, such as
  `job.input_category.file_name = "orders.csv"`. The `upload_file_name` of an `UploadFileJob`, and a
  field of that name on a simple job, are not affected. Mission Control showed and logged it, so
  upgrade Mission Control to a release that supports v8.
* The `on_first:` option of `upload`, deprecated in v7.1, which raises `ArgumentError`. Every record
  of a file without a header row, such as JSON or fixed width, is uploaded, including the first,
  which `on_first` left out. See [Replace on_first](#replace-on_first).

## Upgrading to v7.1

v7.1 prepares an application for v8. It adds a category's `schema`, which replaces the options that
v8 removes, and reports a deprecation warning wherever the application uses one of those. Nothing
else changes: a job that does not use a schema reads and writes its files as it did in v7.0, and the
deprecated options keep working. The other pages of this site describe the latest release; the pages
for v7.1 are on its [v7 branch](https://github.com/reidmorrison/rocketjob/tree/v7/docs).

v7.1 requires IOStreams 2.2, which `bundle update rocketjob` installs. IOStreams 2.2 reports its own
deprecation warnings for what IOStreams 3.0, which v8 requires, removes, see
[Upgrading IOStreams to v2.2](https://iostreams.reidmorrison.com/upgrading.html#upgrading-to-v22).

Servers running v7.0 and v7.1 can run together, but upgrade every server before giving any job,
Dirmon entry or `UploadFileJob` a schema. A v7.0 worker ignores a category's schema, so it would read
the records of such a job by the header row as it is in the file, with every value as text.

### Replace format_options with a schema

A category's `format_options` is deprecated, and replaced by its `schema`, which IOStreams uses for
every tabular format, see [Typed values with a schema](batch.html#typed-values-with-a-schema). A
fixed width layout becomes a schema with the `width` of each field:

~~~ruby
# Before (deprecated)
input_category format:         :fixed,
               format_options: {
                 layout: [
                   {size: 10, key: "name"},
                   {size: 5, key: "zip", type: :integer}
                 ]
               }

# After
input_category format: :fixed,
               schema: {
                 "fieldsMatch" => "subset",
                 "fields"      => [
                   {"name" => "name", "type" => "string", "width" => 10, "truncate" => true},
                   {"name" => "zip", "type" => "integer", "width" => 5}
                 ]
               }
~~~

Each column of the layout is a field of the schema: its `key` is the `name`, its `size` the
`width`, and its `type` the `type`, with `"truncate" => true` on a `string` field, as a layout
truncates a longer value. The table in IOStreams'
[Moving a layout to a schema](https://iostreams.reidmorrison.com/upgrading.html#moving-a-layout-to-a-schema)
gives each of them, including fillers and `:float`. `"fieldsMatch" => "subset"` makes writing skip
the keys of a record that the layout does not list, as a layout did. Leave it out to raise
`IOStreams::Errors::InvalidHeader` for such a key instead, so that a misspelled key is not silently
left out.

A schema reads a fixed width file differently from a layout, so check each job as you move it:

* The keys of the records are the names of the fields, which are Strings. A layout with Symbol keys,
  such as `key: :name`, gave records with Symbol keys, also once a worker read the job back, so add
  `"keyType" => "symbol"` to its schema to keep them, or change `record[:name]` to `record["name"]`
  in `#perform`.
* A value that is not of the type of its field, such as letters in an `integer` field, fails its
  record with `IOStreams::Errors::InvalidValue`.
* The text is read as UTF-8, see [Text is read as UTF-8 with a schema](#text-is-read-as-utf-8-with-a-schema).
* The column options, such as `columns`, cannot be set with a schema. An input category's `columns`
  that narrowed the records of a layout to some of its keys become the fields of the schema.

A layout cannot be set with a schema, since IOStreams would reject them rather than apply one and
ignore the other.

### Replace the column options with a schema

The schema also describes the columns of a file, so the options that described them are deprecated:
an input category's `allowed_columns`, `required_columns`, `skip_unknown` and `header_cleanser`, and the
`columns` of a file without a header row, or of the output to write. So are the same options passed
to `upload`, such as `allowed_columns:`. See [Validating columns](batch.html#validating-columns) and
[Filtering output columns](batch.html#filtering-output-columns).

~~~ruby
# Before (deprecated)
input_category  format:           :csv,
                allowed_columns:  %w[login last_login name state],
                required_columns: %w[login],
                skip_unknown:     true
output_category format: :csv, columns: %w[login last_login]

# After
input_category  format: :csv,
                schema: {
                  "fieldsMatch" => "partial",
                  "fields"      => [
                    {"name" => "login", "constraints" => {"required" => true}, "allowBlank" => true},
                    {"name" => "last_login"},
                    {"name" => "name"},
                    {"name" => "state"}
                  ]
                }
output_category format: :csv,
                schema: {
                  "fieldsMatch" => "subset",
                  "fields"      => [
                    {"name" => "login"},
                    {"name" => "last_login"}
                  ]
                }
~~~

`"allowBlank" => true` keeps a record whose `login` is blank, as `required_columns` did, which only
checked that the file had the column. Leave it out to reject such a record too.

The schema that replaces each option, and each combination of them:

* `"keyType" => "cleansed"` keeps the keys of each record cleansed, as `header_cleanser: :default`,
  the default, did. A column that is not a field, which `"extraColumns" => "keep"` keeps, is keyed
  the same way.
* `required_columns` alone kept every column of the file, so its schema needs `"fieldsMatch" =>
  "subset"` and `"extraColumns" => "keep"`, which keeps them after the fields.
* `header_cleanser: :none` alone becomes `"fieldsMatch" => "subset"`, `"extraColumns" => "keep"` and
  `"fields" => []`, which keeps every column, named as it is in the file.
* A `nil` in the `columns` of a file without a header row becomes a field with `"skip" => true`.
* 7.0 did not apply `allowed_columns`, `required_columns` or `skip_unknown` to JSON records, to the
  `columns` of a file without a header row, or with `header_cleanser: :none`, so leave them out of
  the schema there. With `format: :auto` they applied to CSV and PSV files, but not to JSON files.
* A schema keeps the letters that are not ASCII in a column's name, where 7.0 removed them, so rename
  a field such as `prnom`, for the column `Prénom`, to `prénom`. Otherwise `"partial"`, `"subset"`
  and `"superset"` skip that column without an error.

Before applying a schema to a job, read a recent file of the job with it, and compare the records
with those that the job receives now.

With a schema, the keys of each record are the names of its fields, and the columns of the header row
are matched to them whatever their case, spaces and punctuation, rather than cleansed. So a field
named `last_login` reads the column `Last Login`, and a field named `Last Login` keeps that key.
`fieldsMatch` defaults to `"exact"`: the columns must be the fields, in order, and a column that is not
a field raises `IOStreams::Errors::InvalidHeader`. Use `"subset"` or `"partial"` to skip the other
columns, as `skip_unknown: true` did. See
[Moving the column options to a schema](https://iostreams.reidmorrison.com/upgrading.html#moving-the-column-options-to-a-schema).

The deprecated options cannot be set with a schema, and a category that sets both is not valid. An
input category's `columns` can still be set with a schema, and are not deprecated with one: `upload`
sets them to the header row read from the file, as it is in the file, which the workers match to the
fields.

### Replace the :array upload mode

An input category's `mode: :array`, and the `stream_mode: :array` of `upload`, are deprecated, and
cannot be used with a schema. Use the default `:line` mode, in which each worker parses its lines:

~~~ruby
# Before (deprecated)
input_category format: :csv, mode: :array

# After
input_category format: :csv
~~~

To also parse every line when the file is uploaded, so that a file with a problem is found before it
is processed, give the category a schema and use `:hash`. Without a schema, a category whose files
have a header row, such as CSV, cannot be uploaded in the `:hash` mode in 7.x.

With a schema, both modes upload the lines of the file, so that `#perform` receives each value as its
type, such as a `Date`.

### Replace on_first

The `on_first:` option of `upload` is deprecated, and removed in v8. Its lambda was called with the
header row of a file, or, for a file without one, such as JSON or fixed width, with the first
record, which was then not uploaded.

Rocket Job reads the header row itself, so a lambda that only reads it can be removed. To check the
columns of a file, describe them with the category's schema, which raises
`IOStreams::Errors::InvalidHeader` during the upload when the header row does not match its fields:

~~~ruby
# Before (deprecated)
job.upload(file_name, on_first: ->(header) { raise "No zip column" unless header.include?("zip") })

# After
input_category format: :csv, schema: {"fields" => [{"name" => "name"}, {"name" => "zip"}]}
~~~

To leave out the first record of a file without a header row, such as the control record at the
start of a fixed width file, upload the file with a block that writes every line but that one:

~~~ruby
# Before (deprecated)
job.upload(file_name, on_first: ->(line) { job.control_record = line })

# After
job.upload(file_name: file_name) do |lines|
  first = true
  IOStreams.path(file_name).each(:line) do |line|
    if first
      job.control_record = line
      first              = false
    else
      lines << line
    end
  end
end
~~~

The block reads the file itself, so when it is not UTF-8, give the path its encoding, such as
`IOStreams.path(file_name).encoding("ISO-8859-1")`.

### Text is read as UTF-8 with a schema

The text of a file uploaded into a category with a schema is read as UTF-8, so letters that are not
ASCII, such as `José`, are kept, and text that is not valid UTF-8 raises
`IOStreams::Errors::InvalidEncoding`, and uploads nothing. Without a schema, a tabular upload still
removes every character that is not ASCII, as in v7.0, so moving a job to a schema keeps letters that
it used to lose. An encoding set on the path that is uploaded is used instead.

### Find the deprecated options that you use

Rocket Job reports a Ruby deprecation warning for each deprecated category option that it is given,
naming the line of the job class that defines the category, or of the call to `upload` that supplies
one, such as `stream_mode: :array` or `allowed_columns:`, for example:

~~~
app/jobs/import_job.rb:5: warning: Rocket Job: allowed_columns:, skip_unknown: are deprecated, describe the columns of the file with schema: instead, see https://rocketjob.reidmorrison.com/upgrading.html#upgrading-to-v71
~~~

A Dirmon entry or an `UploadFileJob` whose properties hold a deprecated option reports one when it
builds its job, without the line of a job class.

The warnings are only reported while Ruby's deprecation warnings are on, which they are in tests run
by Minitest, or with `ruby -W:deprecated` or `RUBYOPT=-W:deprecated`, so production stays quiet. A job
that was saved with a deprecated option, and is read back, does not report one. IOStreams reports its
own deprecation warnings, prefixed `IOStreams:`, for the methods and options that the application
calls on it.

### Propose the schema of each category

The warnings name the lines of code, but not the saved documents that hold a deprecated option, such
as scheduled jobs, Dirmon entries and `UploadFileJob`s, since reading one back does not report a
warning. `RocketJob::SchemaProposal` proposes the schema that replaces the deprecated options of each
category, for both, and changes nothing. Run it from a console of the application, once its job
classes are loaded, such as with `Rails.application.eager_load!`:

~~~ruby
puts RocketJob::SchemaProposal.report
~~~

It lists each job class that defines a category with a deprecated option, each saved job that can
still run, and each Dirmon entry and `UploadFileJob` whose properties hold one, for example:

~~~
ImportJob, input category main
  Set: allowed_columns: remove, skip_unknown: false
  Set schema: {"fieldsMatch" => "partial", "fields" => [{"name" => "first_name"}, {"name" => "zip_code"}], "keyType" => "cleansed"}
  Check: A name that 7.0 cleansed from a column with letters that are not ASCII lost them, ...
~~~

Each proposal reads the files as the options did in 7.0, which is not always what they say: options
that 7.0 never applied, such as `allowed_columns` for JSON records, are removed rather than described
in the schema, and the proposal says so. It also says what to check, and when it cannot translate a
category, such as a layout with two columns that have one key, or a job that is already running, which
should finish first. Columns that a scheduled job copied from the header row of an earlier upload are
removed, rather than read as the columns of a file without a header row.

Before applying a proposal, read a recent file of the job with it. `#dry_run` reads the first records
of a file both ways, and lists what differs, such as a key that is no longer read:

~~~ruby
proposal = ImportJob.schema_proposals.first
proposal.dry_run("/data/in/orders_20261020.csv")
# => ["Record 1: keys no longer read: [\"prnom\"]"]
~~~

Then apply it by hand: in the job class, replace the deprecated options with the schema, and for a
saved job, Dirmon entry or `UploadFileJob`, set the same in its category, or its properties. Mission
Control 7.0 cannot show or set a schema, and saving a Dirmon entry in it rebuilds the entry's
properties without one, so set the schema on the job class where you can, or from a console.

## Upgrading to v6

- Support for Ruby v3 and Rails 6.
- Major enhancements in Batch job support:
    - Direct built-in Tabular support for all input and output categories.
    - Multiple output file support, each with its own settings for:
        - Compression: GZip, Zip, BZip2 (chunked for much faster loading into Apache Spark).
        - Encryption: PGP, Symmetric Encryption.
        - File format: CSV, PSV, JSON, Fixed Format, xlsx.
- Significant error handling improvements, especially around throttle failures that used to result
  in "hanging" jobs.
- Removed use of Symbols to meet the Symbol deprecation in MongoDB and Mongoid.

### Deprecated Tabular plugins

The following plugins have been deprecated and are no longer loaded by default.

- `RocketJob::Batch::Tabular::Input`
- `RocketJob::Batch::Tabular::Output`

If your code relies on these plugins and you still want to upgrade to Rocket Job v6, add the
following require statement to any jobs that still use them:

~~~ruby
require "rocket_job/batch/tabular"
~~~

It is important to migrate away from these plugins, since they will be removed in a future release.

### Scheduled jobs

For any scheduled jobs that include the `RocketJob::Plugins::Cron` plugin, the default behavior has
changed so that the scheduled job instance is created immediately after the currently scheduled
instance starts.

To maintain the old behavior of creating the job when it fails, aborts, or completes, add the
following line to each of the applicable jobs:

~~~ruby
self.cron_after_start = false
~~~

Additionally, scheduled jobs now prevent a new one from being created when another scheduled
instance of the same job is already queued, or running with the _same_ `cron_schedule`.

To maintain the old behavior of allowing multiple instances with the same cron schedule, add the
following line to each of the applicable jobs:

~~~ruby
self.cron_singleton = false
~~~

Since scheduled jobs now implement their own singleton logic, remove the singleton plugin from any
scheduled jobs.

### Batch jobs

Rocket Job v6 replaces the array of symbols for `input_categories` and `output_categories` with an
array of `RocketJob::Category::Input` and `RocketJob::Category::Output`.

Jobs that added or modified the input or output categories need to be upgraded. For example:

~~~ruby
class MyJob < RocketJob::Job
  include RocketJob::Batch

  self.output_categories = [:main, :errors, :ignored]
end
~~~

Needs to be changed to:

~~~ruby
class MyJob < RocketJob::Job
  include RocketJob::Batch

  output_category name: :main
  output_category name: :errors
  output_category name: :ignored
end
~~~

#### slice_size, encrypt, compress

These fields have been removed from the job itself:

~~~ruby
class MyJob < RocketJob::Job
  include RocketJob::Batch

  self.slice_size = 1_000
  self.encrypt    = true
  self.compress   = true
end
~~~

They are now specified on the `input_category` as follows:

- `slice_size` just moves under `input_category`.
- `encrypt` becomes an option to `serializer`.
- `compress` is now the default for all batch jobs, so it is not needed.

If the serializer is set to `encrypt` then it is automatically compressed.

~~~ruby
class MyJob < RocketJob::Job
  include RocketJob::Batch

  input_category slice_size: 1_000, serializer: :encrypt
end
~~~

#### collect_output, collect_nil_output

The following fields have been moved from the job itself:

~~~ruby
class MyJob < RocketJob::Job
  include RocketJob::Batch

  self.collect_output     = true
  self.collect_nil_output = true
end
~~~

Into the corresponding `output_category`:

- `collect_output` no longer has any meaning. Output is collected anytime an `output_category` is
  defined.
- `collect_nil_output` is now the option `nils` on the `output_category`. It defaults to `false` so
  that by default any `nil` output from the `perform` method is not collected.

~~~ruby
class MyJob < RocketJob::Job
  include RocketJob::Batch

  output_category nils: true
end
~~~

#### Category name

For both `input_category` and `output_category`, when the `name` argument is not supplied it
defaults to `:main`. For example:

~~~ruby
class MyJob < RocketJob::Job
  include RocketJob::Batch

  input_category name: :main, serializer: :encrypt
  output_category name: :main
end
~~~

Is the same as:

~~~ruby
class MyJob < RocketJob::Job
  include RocketJob::Batch

  input_category serializer: :encrypt
  output_category
end
~~~

#### Existing and in-flight jobs

When migrating to Rocket Job v6, it is recommended to load every job and then save it back again as
part of the deployment. When the job loads it will automatically convert itself from the old schema
to the new v6 schema.

In-flight jobs should not be affected, other than it is important to shut down all running batch
servers _before_ running any new instances.

## Upgrading to v3

V3 replaces MongoMapper with Mongoid, which supports the latest MongoDB Ruby client driver.

### Mongo config file

Replace `mongo.yml` with `mongoid.yml`. Start with the sample
[mongoid.yml](https://github.com/reidmorrison/rocketjob/blob/main/test/config/mongoid.yml).

Note: the `rocketjob` and `rocketjob_slices` clients in the above `mongoid.yml` file are both
required.

### Other changes

Arguments are no longer supported. Use fields for defining all named arguments for a job.

Replace usages of `rocket_job do` to set default values:

~~~ruby
rocket_job do |job|
  job.priority = 25
end
~~~

With:

~~~ruby
self.priority = 25
~~~

Replace `key` with `field` when adding attributes to a job:

~~~ruby
key :inquiry_defaults, Hash
~~~

With:

~~~ruby
field :inquiry_defaults, type: Hash, default: {}
~~~

Replace usage of `public_rocket_job_properties` with the `user_editable` option:

~~~ruby
field :priority, type: Integer, default: 50, user_editable: true
~~~
