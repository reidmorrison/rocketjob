# Change Log

All notable changes to this project will be documented in this file.
This project adheres to [Semantic Versioning](http://semver.org/).

## [Unreleased]

### Breaking changes

- Removed the category options that Rocket Job 7.1 deprecates, since a category's `schema` replaces them:
  - `format_options`, the layout of a fixed width file. A category with `format: :fixed` needs a schema, with the
    `width` of each field, without which IOStreams 3.0 raises `ArgumentError`.
  - An input category's `allowed_columns`, `required_columns`, `skip_unknown` and `header_cleanser`, and an output
    category's `columns`. The same options supplied to `upload`, such as `allowed_columns:` or `cleanse_header:`,
    raise `ArgumentError`. A `:csv`, `:psv` or `:fixed` output category needs a schema, whose fields are the columns
    that it writes.
  - An input category's `columns`, for a file without a header row: they only hold the header row that `upload` read
    from a file without a schema. Uploading a file into a category whose `columns` no upload read raises
    `ArgumentError`, rather than reading the file by them, as does reading the records of a category saved with
    columns that were not cleansed. Also removed `#cleanse_header!` of an input category, which cleansed
    them.
  - The `:array` upload mode, an input category's `mode: :array` and the `stream_mode: :array` of `upload`. An
    upload raises `ArgumentError` for it, also for a category saved with it, which stays valid, so that the next run
    of a scheduled job with it is still created. The Arrays of a file that Rocket Job 7 uploaded in the `:array` mode
    are still processed.

  A job class that defines a category with one raises `ArgumentError` when it is loaded, naming it, and so does a
  Dirmon entry or an `UploadFileJob` whose properties hold one when it builds its job, which also fails validation
  when it is saved. A category that was saved with one, such as that of a scheduled job, raises `ArgumentError` when it
  reads or writes its records, rather than reading them as though the option were not set. An option that is blank, or
  at its default, such as a blank `format_options`, or `skip_unknown: false`, which Rocket Job 7 saved with every
  input category, is ignored. Upgrade to 7.1 first, and replace each one there, since its deprecation warnings and
  `RocketJob::SchemaProposal.report` find them, which v8 does not have, see the upgrade guide.
- Removed `RocketJob::Plugins::Restart`, deprecated in v6, use `RocketJob::Plugins::Cron`; `RocketJob::LookupCollection`,
  which was unused, and whose `upload` always raised `ArgumentError`; and `#work_first_slice` of a batch job,
  deprecated in v6. A batch job saved by v5, and never saved since, is no longer translated into v6 categories when
  it is read. See the upgrade guide.
- Removed the batch job methods `upload_arel`, `upload_mongo_query`, `upload_integer_range` and
  `upload_integer_range_in_reverse_order`, deprecated in v6. Call `upload` with the relation, query or range instead,
  such as `upload(User.where(country_code: "US"), columns: %i[name zip_code])` or `upload(200..421)`, including in
  the `before_code` of an `OnDemandBatchJob`, whose documentation showed `upload_arel`. Also removed
  `upload_file_name` and `upload_file_name=` of a batch job, deprecated in v6, which read and set the `file_name` of
  its input category: use `input_category.file_name` instead. See the upgrade guide.
- `upload` of an Active Record relation reads it with IOStreams 3.0, as one query that the database streams, rather
  than with `find_each`, without building a model for each row. The rows are uploaded in the order of the relation,
  and within its limit, where Rocket Job 7 uploaded them in the order of their ids. Each column is read as `pluck`
  reads it, so a reader that the model overrides is not called. The query is read on a connection of its own, so it
  uploads the rows that were committed, rather than those that an open transaction of the caller wrote, and the pool
  of the model needs a connection free besides that of the caller. The query stays open until every row is uploaded,
  so upload a very large table in batches. A database whose driver cannot stream a query raises `ArgumentError`:
  any but PostgreSQL, MySQL with `mysql2`, or SQLite with `sqlite3`. Upload the batches of the relation instead. A
  relation that loads associations with `includes` raises `ArgumentError`, also in batches: join their tables with
  `joins` instead. A relation, and its batches, need Active Record 7.2 or later, and raise `ArgumentError` for an
  earlier version, where a block of `upload` can write the records instead. `upload` still raises `ArgumentError` for
  a query with a block: write the records in a block of `upload` instead. See the upgrade guide.
- `.from_properties(nil)` of a batch job builds a job with the defaults, as it does for a job that is not a batch
  job. Previously it raised `NoMethodError`, such as when Mission Control saved a Dirmon entry for a batch job
  without changing its properties.
- A batch job that is retried, or requeued, while in `before_batch` removes the slices that its `before_batch`
  callbacks uploaded, and restores its `record_count`, and the file name, format, columns and header row of each input
  category, as they were when the callbacks started, so that they upload the input again without duplicating it.
  Previously the slices that they uploaded were kept, so a retry uploaded the input a second time. Slices uploaded
  before the job started are kept. Each slice uploaded by `before_batch` records it in its new `upload_id`, and the
  job keeps what it restores in its new `before_batch_state` while the callbacks run.
- Uploading a second file with a header row into an input category without a `schema`, which holds the header row of
  an earlier upload, in the `:line` mode, raises `ArgumentError` and uploads nothing. Previously the second file's header
  row was stored as a record, and its lines were read with the first file's columns. A second file uploaded in the
  `:hash` mode also raises. Upload each file into its own input category, or upload every file in the `:hash` mode,
  in which each record keeps the columns of its own file. An input category records that its `columns` hold the
  header row of an upload in its new `header_uploaded`, which an upload that fails clears, with the columns, so
  that a retried job can upload its file again. See the upgrade guide.
- `RocketJob::Plugins::Transaction` wraps each slice of a batch job in a transaction, and
  `RocketJob::Plugins::ThrottleDependentJobs` throttles its slices, whether the job includes them before or after
  `RocketJob::Batch`, as documented. Previously a job that included `Transaction` first had a transaction around
  each record instead, and one that included `ThrottleDependentJobs` first did not throttle its slices.
- `RocketJob::Plugins::Singleton` does not save a job while another of its class is paused, as its documentation
  and its error message say. Previously only a running or queued job prevented it.
- Dirmon only skips the files in its archive directory, and in the directories within it: within a directory named
  as a relative `archive_directory`, such as `archive`, below the directory that the entry's pattern starts in, or
  within an absolute one. Previously it skipped every file whose path contained the name of the archive directory
  anywhere, such as `archived_orders.csv`, the files in `/data/archive_2026`, or every file that a pattern such as
  `/srv/archive/incoming/*.csv` matched, so those files are processed after the upgrade. Move such files elsewhere
  first if they must not be processed.
- Uploading a range of integers, such as `upload(200..421)`, returns, and adds to `record_count`, the number of
  integers in it, 222, where it was the number of ranges, one per slice of `slice_size` integers, 3. So
  `percent_complete` follows the ranges as they are processed, where it stayed 0 until the job completed. Each slice
  still holds one `[first_id, last_id]` record. What reads `record_count` counts the integers too:
  `RocketJob::Batch::LowerPriority` lowers the priority of such a job by one for each `lower_priority_count`
  integers, rather than ranges, and the `records_per_hour` of its `status` is the integers processed per hour.
- Uploading a range that excludes its end, such as `upload(200...421)`, does not upload that end. Previously it was
  uploaded, as if the range were `200..421`. A range without an end or a beginning, such as `200..`, raises
  `ArgumentError`, where it raised `RangeError`, and a descending range of negative integers, such as `-1..-25`,
  uploads each integer once. Previously each of its slices started at its lowest integer, so they overlapped.
- Require IOStreams 3.0, and so Ruby 3.3 or later, which IOStreams 3.0 requires (was Ruby 3.2).
- Uploaded files are read as UTF-8 text, and a UTF-8 byte order mark at the start of a file is removed.
  Previously the lines were binary strings, so uploading any file with a non-ASCII character, without
  setting `option(:encode, encoding: "UTF-8")` on the path, raised `Encoding::UndefinedConversionError`
  when the slice was saved. A file that is not valid UTF-8 still raises
  `Encoding::UndefinedConversionError`, now while it is read, unless its encoding is set on the path,
  for example `IOStreams.path("file.csv").encoding("Windows-1252:UTF-8")`.
- Tabular uploads, such as CSV, keep non-ASCII characters. Previously every non-ASCII character was
  removed, so `José` was uploaded as `Jos`. Non-printable characters, and characters that are not
  valid in the file's encoding, are still removed.

  Both changes fix data handling, but any code that depends on uploaded records being ASCII only, for
  example a fixed width layout, a downstream system that rejects other characters, or a comparison
  with previously processed output, will now see the non-ASCII characters. To keep removing them
  from a tabular upload, set the encoding on the path:

  ~~~ruby
  job.upload(IOStreams.path("file.csv").encoding("US-ASCII"))
  ~~~
- Fixed width uploads are read as ASCII, which IOStreams 3.0 uses for the fixed width format, so a file
  with any other character raises `IOStreams::Errors::InvalidEncoding` and nothing is uploaded.
  Previously each byte of a character that is not ASCII became a space. Set the file's encoding on the
  path to keep its characters, such as `IOStreams.path("file.txt").encoding("ISO-8859-1:UTF-8")`, or
  `"IBM037:UTF-8"` for EBCDIC, or `encoding("UTF-8")` when the sizes count UTF-8 characters, or
  `encoding(replace: " ")` to replace them with spaces as before.
- Fixed width output is downloaded as ASCII, so a value that is not ASCII raises
  `Encoding::UndefinedConversionError` when the output is downloaded. Previously it was written as UTF-8,
  so a line with such a character was longer, in bytes, than its layout, which a program that counts
  bytes, such as one on a mainframe, reads into the wrong columns. Set the encoding of the download path,
  such as `IOStreams.path("file.txt").encoding("ISO-8859-1")`, or `encoding(replace: " ")`.
- Output written by the `:bz2` and `:encrypted_bz2` serializers is written in the output category's
  `encoding`, or the format's own, such as ASCII for fixed width, when each slice is written, since its
  slices are downloaded as they are. So fixed width output with a value that is not ASCII now fails its
  slice, where it was written as UTF-8, a line longer than its layout. Set the output category's
  `encoding`, such as `"ISO-8859-1"`. An encoding set on the download path of such output raises
  `ArgumentError`, where it changed the compressed data.
- A fixed width `:integer` or `:float` column that holds text that is not a number, such as `N/A`, fails
  its record with `IOStreams::Errors::InvalidValue`, as IOStreams 3.0 reads it. Previously it was read as
  `0`, or as the number that its leading digits make. Writing a fraction to an `:integer` column also
  raises, where it was truncated.
- `upload` raises `ArgumentError` when it is given `format:`, `format_options:`, `schema:` or
  `default_format:`, since IOStreams 3.0 reads them only from the path. Set them on the input category,
  or on the path that is uploaded, instead.
- A `Time` that a job returns to a CSV, PSV or fixed width output category is written in ISO 8601, such as
  `2026-10-13T09:30:00Z`, where it was `2026-10-13 09:30:00 UTC`. A JSON output category writes all of its fraction of a second, such as
  `2026-10-13T09:30:00.123456Z`, where it was `2026-10-13T09:30:00.123Z`, and none for a whole second, such as
  `2026-10-13T09:30:00Z`, where it was `2026-10-13T09:30:00.000Z`, as IOStreams 3.0 writes them.
- A header row is cleansed as IOStreams 3.0 cleanses it, which keeps the letters and digits that are not ASCII, and
  treats whitespace that is not ASCII, such as a no-break space, as a space. So the column `Prénom` is `prénom`,
  where it was `prnom`, and `First Name` with a no-break space is `first_name`, where it was `firstname`, which
  changes the keys of the records that `#perform` receives, without a schema.
- A Dirmon entry, and an `UploadFileJob`, check the category properties that they hold for a batch job when
  they are saved, so an entry, or an `UploadFileJob`, that was saved before can now fail validation and
  must be corrected before it can be saved again:
  - Each value is validated, such as an `encoding` that is not valid, or an `invalid_characters` that is
    not one of its values. Previously the values were only checked when the job was created, so every file
    that a Dirmon entry found failed.
  - The names of the category properties are checked for a batch job. Previously only those of a job
    without categories were checked.
  - A category that the job does not define, such as an output category of a job without any, is rejected.
  - `input_categories` and `output_categories` must each be a list of the properties of each category.
  - A job without categories rejects `input_categories` and `output_categories`, since it cannot be built
    from them. Previously their names were checked as though it had categories.

  Each error names the category, such as `Input category main: Encoding "UTF-16" writes a byte order
  mark ...`, or `Input category main: Unknown property: blah`, which replaces the message
  `Unknown Property in input_categories: Attempted to set a value for blah.input_categories ...`.
  The job class decides, see `.property_errors`, and asks each category, see
  `RocketJob::Category::Base#property_errors`, without building the job.
- `.from_properties` of a batch job merges category properties whose keys are Symbols onto the categories
  that the job defines, as it did for String keys. Previously they replaced the job's categories.

### Security

- A Dirmon whitelist path only admits the files within that directory. Previously it admitted any path that started
  with the same characters, so the whitelisted `/data/in` also admitted the files of `/data/inbox` and
  `/data/in_other`.
- With `format: :auto`, renaming an upload from `.csv` to `.json` bypassed `allowed_columns` and
  `required_columns`, which are removed, see above. The schema that replaces them also applies to the keys of
  JSON records.
- Dirmon's log messages, the original file name that it records on each `UploadFileJob`, and its list
  of the files waiting to stabilize, no longer include the user name, password or query of a url, such
  as `sftp://user:password@host/file.csv`, and neither does the description of a `CopyFileJob`. They
  use the display name of the path, see `IOStreams::Path#display_name`. A file that is waiting to
  stabilize when Dirmon is upgraded is picked up one scan later, since that list is now also keyed by
  the entry.

### New features

- A batch job parses each record in its input category, and renders each result in its output category, in the
  loop that processes its slices, rather than in perform callbacks. So a batch job without perform callbacks of its
  own skips running them for each record, which doubled the records per second of a job whose `#perform` does no
  work, from 59,000 to 117,000, or 43,000 to 93,000 with output. Callbacks see the same values as before: the parsed
  record in `before_perform`, and the result of `#perform` before it is rendered in `after_perform`, except for a
  perform callback defined before the job includes `RocketJob::Batch`, which now also sees the parsed record, and the
  result before it is rendered.
- `upload` uploads the batches of an Active Record relation, `relation.in_batches(...)`, for a database whose driver
  cannot stream a query, such as MySQL with `trilogy`: the columns that the relation selects, such as
  `job.upload(User.select(:id).in_batches(of: 10_000))`, read on the connection of the caller. Batches whose
  relation selects no columns raise `ArgumentError`, rather than upload every column.
- A job plugin runs its batch setup, such as defining a batch throttle or a slice callback, in a
  `rocket_job_batch_plugin` block, which runs in the job class once it includes `RocketJob::Batch`, so the plugin
  works whether a job includes it before or after `RocketJob::Batch`. `Transaction` and `ThrottleDependentJobs`
  use it.
- A category's `schema` is a Frictionless Table Schema, as a Hash, or the path or url of a JSON file,
  that IOStreams 3.0 uses to read each value of its records as its type, such as an `Integer`, a
  `BigDecimal` or a `Date`, and to write each value in the text form of its type, for every tabular
  format. It also gives the position of each field of a fixed width file, and `"header" => false`
  describes a file without a header row. It is set on the path that is uploaded, and validated when the
  category is saved, without reading a file that holds it.

  The schema also describes the columns of a file. Each column of the header row, or key of a JSON
  record, is matched to a field by its name or one of its `aliases`, whatever its case, spaces and
  punctuation, and the keys of each record are the names of the fields. Its `fieldsMatch` says which
  columns a file can have, and `"constraints" => {"required" => true}` which fields it must have. An
  uploaded header row that does not match raises `IOStreams::Errors::InvalidHeader`, and nothing is
  uploaded. Each slice of a file uploaded into an input category holds its header row, see below. An output
  category writes the names of the fields as its header row, and the fields of each result, in order.
- `upload` reads a file into an input category with a `schema` with IOStreams' `each(:slice)`, rather than splitting
  it into slices itself: IOStreams reads up to `slice_size` rows at a time, after the header row, which it matches to
  the fields before any slice is uploaded, and each slice holds the header row of its file. So the category's
  `columns` are not set, and files whose columns are in another order can be uploaded into the same input category,
  one after another. In the `:hash` mode IOStreams also reads each row while the file is uploaded, so
  that a file with a value that is not valid uploads nothing, but the slices hold the lines as they are, and a `date`
  reaches `perform` as a `Date`. A row that cannot be read fails its record, and a retry processes the slice again
  from that record. `on_first` is called with a copy of the header row as an Array of its columns, or for a file
  without one, such as JSON, with its first line, which is not uploaded. A worker of Rocket Job 7 fails such a slice,
  rather than processing no records, see the upgrade guide. The workers read each slice with the category's schema,
  so uploading a path that has another schema set on it raises `ArgumentError`. Assigning an Array of rows to the
  `records` of such a slice, such as a changed copy of them, keeps its header row and format.
  The lines that the block of `upload` writes for such a category are read in the same slices, after the header row
  read from the first lines, and a record written to it that is not a line, such as a Hash, raises `ArgumentError`.
  The lines written before the block breaks out are uploaded, as without a schema.
- `CopyFileJob` converts the text of a file from its `source_encoding` to its `target_encoding`, such as
  `source_encoding: "Windows-1252"`, which copies a file that Excel saved on Windows as UTF-8. When only one
  is set, the other is UTF-8, and when neither is set the file is still copied byte for byte. The text is
  converted between the streams taken from the file names, so a `.gz` file is decompressed first, and
  compressed again. Previously a copy could only convert the text with an `encode` entry in
  `source_streams` or `target_streams`, which stopped the streams being taken from the file name, so a
  `.gz` file was no longer decompressed.
- Input and output categories have an `encoding`, such as `input_category format: :csv, encoding:
  "Windows-1252"`, the encoding of the text in their files. An uploaded file is converted from it to UTF-8,
  and a downloaded file is converted to it from UTF-8, such as `"ISO-8859-1"` or `"IBM037"` for a fixed
  width file for a mainframe. It is saved with the job, so it also applies when a worker uploads the
  category's file, as a `ConversionJob` does, and a Dirmon entry can set it for its files in its
  `properties`, such as `input_categories: [{name: "main", encoding: "Windows-1252"}]`. Previously the
  encoding could only be set on a path supplied to `upload` or `download`, which still takes its place,
  so the characters of such a file uploaded by file name were removed, or raised. The `encoding` must name
  one encoding of text that Ruby converts to and from UTF-8, so `"locale"`, `"BINARY"` and `"UTF-7"` are
  not valid, nor are `"UTF-16"` and `"UTF-32"`, which write a byte order mark in front of each slice:
  name their byte order instead, such as `"UTF-16LE"`. The same applies to a `CopyFileJob`'s encodings.
- An input category's `invalid_characters` sets what an upload does with each character that is not
  valid in the file's encoding: `:remove` it, `:replace` it with U+FFFD, or `:raise`
  `IOStreams::Errors::InvalidEncoding`, which names the line of the first one, and upload nothing. By
  default tabular formats, such as CSV, still remove them, while fixed width files and lines still raise.
  A `replace:` set on the path supplied to `upload` is now used instead, where a tabular upload replaced
  it with its own.
- A Dirmon entry whose storage cannot be reached, such as an SFTP server that is restarting, is
  scanned again on the next run instead of failing, until its storage has been unavailable for longer
  than `RocketJob::DirmonEntry.max_unavailable_seconds`, an hour by default. Previously the first
  `IOStreams::Errors::Unavailable` failed the entry, so it stopped scanning until someone re-enabled
  it. Set `max_unavailable_seconds` to `0` to keep the previous behavior. On Ruby 3.3 and later, a host
  name that does not exist, such as a mistyped one, is not reported as unavailable, so it still fails the
  entry on the first scan.
- `RocketJob.path_display_name` returns a path or url to show, for example in Rocket Job Mission Control,
  without the user name, password or query of a url. A value that is not a valid path, or that needs a gem
  that is not installed, is shown as `(not a valid path)`.
- `RocketJob::DirmonEntry#pattern_display_name` and `#archive_directory_display_name` return the pattern
  and archive directory to show, see `RocketJob.path_display_name`. A remote pattern with characters that
  a url cannot hold, such as `sftp://host/in/*.{csv,txt}`, is shown as the directory it scans followed by
  the pattern within it. `#display_properties` returns its properties with the paths in them, as declared
  by its job class, shown without credentials.
- `RocketJob::Job#display_attributes` returns the attributes of a job to show, with each path or url field
  shown without its credentials. A field is a path when it is declared with `path: true`, such as the
  `source_url` and `target_url` of `CopyFileJob`, or has the type `IOStreams::Path`. `.path_fields` lists them.
  The `file_name` of each input and output category of a batch job is also shown without its credentials,
  and so are the paths in the `properties` of an `UploadFileJob`. `.display_properties` does the same for
  a hash of properties for a job class, such as those of a Dirmon entry.
- `CopyFileJob#display_attributes` also replaces the secrets in `source_args`, `target_args`,
  `source_streams` and `target_streams`, such as an SFTP password or a PGP passphrase, as decided by
  `IOStreams.redact_path_options` and `IOStreams.redact_stream_options`.
- A `CopyFileJob` checks its source and target when it is created, or when their url, arguments or
  streams change, by building each path, so a url that is not valid, or an argument or stream option that
  the path does not accept, such as a misspelled `passwrd:`, fails validation instead of failing the job
  when it runs. Encrypted arguments are not decrypted to check them. A value of the wrong type is reported
  without including it in the message, since it could be a secret.
- `RocketJob::DirmonEntry#replicate` returns a new, pending entry with the settings of an entry, such as
  its job class and properties, overridden by the supplied attributes. Only its name, pattern, job class,
  properties and archive directory are copied. Since the name and pattern must each be unique, the new
  entry is not valid until both are changed.

### Fixes

- When an upload raises, only the slices that it stored are removed, so the slices of an earlier upload into the same
  input category, such as the first of two files, are kept. Previously the whole input collection was removed, while
  the job's `record_count` still counted the earlier records, so the job completed without processing them. The
  slices of an upload into an input collection that already holds slices record it in their `upload_id`.
- A slice whose records cannot be read, such as one encrypted with a key that the worker does not have, fails with
  that error when it is processed. Previously reading it raised as the worker claimed it, which stopped that worker
  thread, and left the slice running under its name until the server restarted.
- An upload of a tabular file that starts with blank lines, such as a CSV file, skips them and reads the header row
  after them, as IOStreams does. Previously the first blank line was taken as the header row, so the header row was
  uploaded as a record, and with a schema every slice then failed, since the header row had not been read. The
  `on_first` lambda is called with the header row.
- An input category with `format: :auto` uploads the first record of a JSON file. Previously it was dropped, as
  though it were a header row, so `record_count` was one short.
- A category accepts a `format` that the application registers with IOStreams after Rocket Job is loaded, see
  `IOStreams.tabular_formats`. Previously the formats were read when Rocket Job was loaded, so such a format failed
  validation.
- The Active Job adapter works with `config.active_job.queue_adapter = :rocket_job`, for which Active Job creates an
  instance of the adapter. Previously the adapter only had class methods, so `perform_later` raised `NoMethodError`.
  It now extends `ActiveJob::QueueAdapters::AbstractAdapter` when Active Job defines it, and its class methods
  still work, including `enqueue_after_transaction_commit?`, which Active Job 7.2 asks an adapter that is assigned
  as a class.
- `cron_singleton = false` allows another job with the same `cron_schedule` to be queued, as documented, and as the
  v6 upgrade guide prescribes to keep the behavior before v6. Previously the setting was ignored, so the second job
  failed validation.
- The `--name` option of the `rocketjob` command sets the name of the server. Previously it raised `NoMethodError`.
- The `--pidfile` option of the `rocketjob` command writes the id of the process. Previously the file was empty
  unless a gem that the application loaded had required Ruby's `English` library.
- A category reads and writes its records with a field that is set after it was first used, such as an output
  category's `schema` or `format`. Previously it kept using the values that it had when it first read or wrote a
  record, so for example the header row of a download did not change.
- A batch job in the `after` sub-state that a worker works on, such as one processed with `#perform_now`, runs its
  `after_batch` callbacks and completes. Previously the worker skipped them, so the job stayed running.
- A worker event, such as `RocketJob::Subscribers::Worker.publish(:stop, server_id: id.to_s, worker_id: 1)`,
  acts on the server whose id it names as a String too, as a server event does. Previously the id only matched
  when it was published as a `BSON::ObjectId`.
- A batch job class that defines an input or output category, such as `input_category name: :other`, no longer
  changes the categories of its parent class. Previously it added the category to, or replaced the category with
  the same name in, the parent class and its other subclasses too, which shared the list. So which categories a
  job of the parent class had, and their settings, such as `slice_size`, depended on which of its subclasses had
  been loaded.
- An exception raised while a batch job's slice is already failed is recorded on the slice. Previously it was lost,
  and the slice kept the exception of its first failure.
- `undefine_batch_throttle` in a subclass removes the throttle from that subclass only. Previously it also removed
  it from the parent class, and from every other subclass of the parent, since they shared the list of throttles.
- The jobs and slices of a server that died are requeued only when a worker on that server was processing them.
  Previously the server's name was matched as a prefix, so the server `host:12` also requeued the jobs and slices
  of `host:123`, which were still being processed, and `RocketJob::ActiveWorker.all("host:12")` listed its
  workers. Likewise the server `host` no longer requeues those of `host:2`. For a batch job that is processing its
  slices, `RocketJob::ActiveWorker.all("host:12")` lists the workers processing them on that server, where it listed
  those of every server, or none, depending on which worker started the job. The name of a server is also read back
  correctly from the names of its workers when it has no colon, such as `RocketJob::Config.server_name = "worker1"`,
  so `HousekeepingJob` no longer requeues the jobs that the workers of such a running server are processing.
- An upload in the `:hash` mode of a tabular input category reads with IOStreams 3.0. The
  category sets its format on the path that it reads, since IOStreams no longer accepts it for each read.
- A category's `encoding`, and `CopyFileJob#source_encoding` and `#target_encoding`, can be `"UTF-8"`.
  Previously it was rejected as an encoding that Ruby cannot convert to and from UTF-8, since Ruby has no
  converter from UTF-8 to itself.
- An upload of records, such as with a block, or of a query, that holds text that is
  binary or not valid UTF-8 raises an error that names the number of the first such record, such as
  `Cannot upload record 4, since MongoDB only stores UTF-8 text: ...`, or `record 4 after the header`
  when the upload started with a header row, since the record is then on the next line of the file.
  Previously the error from BSON did not say which record it was. Nothing is uploaded, as before.
- A worker that resumes a slice whose output is written by the `:bz2` or `:encrypted_bz2` serializer, such
  as after its server restarted, appends the records that it writes as another BZip2 stream. Previously
  the compressed records already in the output slice were compressed again with the new ones, so the
  slice could not be read when the output was downloaded.
- Downloading output written by the `:encrypted_bz2` serializer with a header line, such as CSV output,
  writes the header line. Previously it raised `NotImplementedError`.
- Dirmon processes a file on an SFTP server whose name is not ASCII, such as `café.csv`. Net::SFTP lists
  each name as binary, so the name that a scan recorded in the `DirmonJob` was read back as UTF-8, and
  never matched the name that the next scan found. The file was logged as found on every scan, and never
  processed.
- Dirmon processes a file whose name is not valid UTF-8, such as `café.csv` written in Latin-1 by a
  Windows program to a Linux file system, which IOStreams 3.0 lists. MongoDB only stores UTF-8, so the
  file is archived under its name with each such byte replaced by U+FFFD, after the job id as before, and
  the upload job's original file name and description show each such byte as `\xHH`. Dirmon also logs,
  and records in the `DirmonJob`, each file name as valid UTF-8.
- Dirmon skips a file whose directory is not writable by the current user, logging a warning, since the
  file cannot be moved to the archive directory. The check never ran, since IOStreams paths do not
  implement `writable?`, so such a file failed its Dirmon entry instead.
- A batch job that restarts, such as the next run of a scheduled job with `cron_after_start: false`, reads the
  header row of its own upload. Previously it kept the header row that the previous run's upload read, so the next
  file's header row was stored as a record, and its lines were read with the previous file's columns. A job saved by
  v7 keeps that header row, so the upload of its next run raises `ArgumentError` until it is cleared, see the upgrade
  guide.
- A Dirmon entry whose job class cannot receive a file, since it is not a batch job and has neither an
  `upload_file_name` nor a `full_file_name` field, is not valid, as the Dirmon guide says. Previously it
  was saved, then the first file that it found was archived, the `UploadFileJob` for it was rejected, so
  no job processed the file, and the entry failed. Dirmon also fails the entry, and leaves the file where
  it is, when its job class can no longer receive a file, such as after the class changed.
- Dirmon skips the files in an absolute `archive_directory` that is reached through a symbolic link, such
  as `/data/archive` when it links to `/mnt/storage`. A scan finds each file by its real path, which did
  not contain the archive directory as it was set, so the archived files were processed again.
- A job, or a batch job's slice, whose exception message is not valid UTF-8 is failed and saved, with each
  such byte shown as `\xHH`. Previously saving the failure raised `EncodingError`, which left the job, or
  the slice, `running` with no exception recorded until its server restarted, so a batch job never
  completed. Such a message comes, for example, from a `JSON::ParserError` for a response body that is not
  UTF-8. The same holds for a message in an encoding that ASCII is not part of, such as UTF-16LE, with a
  byte that is not valid in it. A message that is UTF-8 held as binary keeps its characters, where previously each character that is not ASCII was removed, so
  `José` was saved as `Jos`. The same applies to a Dirmon entry's exception.
- A `CopyFileJob` fetches its `secret_config_` arguments from Secret Config even when Symmetric Encryption
  is not loaded. Previously they were passed to IOStreams under their stored names, which failed the job.
  A source or target whose streams are `nil` copies without any streams, instead of raising `NoMethodError`.
- A tabular upload, such as CSV, uses the encoding set on the path, such as `encoding("Windows-1252:UTF-8")`.
  Previously it was always replaced with UTF-8, so the characters of a Windows-1252 file that are not
  ASCII were removed.
- An input category's `mode` of `:hash` is used by `upload`. Since v6.0.0 `upload` read the file a line
  at a time unless `stream_mode` was supplied, and the category's `mode` only changed how the header
  row was read, so with `:hash` the workers raised `ArgumentError` because the header columns were not
  set. The `stream_mode` of `upload` still overrides it.
- Hashes uploaded with `mode: :hash`, or `stream_mode: :hash`, are no longer parsed again by the workers.
  Previously a worker tried to parse them again in the category's format, which raised for CSV.
- Non-printable characters in a fixed width upload, such as NUL padding, are replaced with spaces.
  Previously they were removed, which moved the columns after them, so the line raised
  `IOStreams::Errors::InvalidLineLength`.
- A quoted CSV value that contains a line break is uploaded as one record, whatever the file name.
  Previously, when the file name did not end in `.csv`, the line was split at the line break.
- Dirmon skips a file that is removed after a scan finds it, instead of failing its entry.
  Previously a local file that was removed while it was being checked or archived failed its entry
  with `Errno::ENOENT`, as did a file removed from S3 while it was being archived. Dirmon rescues
  `IOStreams::Errors::NotFound`, so this applies to every storage, now that IOStreams 3.0 raises it
  from `#size` for a missing S3, SFTP or HTTP file, where 2.x returned nil. A missing archive
  location, such as an S3 bucket that does not exist, still fails the entry.

## [7.0.0] 2026-09-05

### Breaking changes

- Raise minimum dependency versions: Ruby 3.2 (was 2.7), Mongoid 8.1 (was 7.5),
  Semantic Logger 5.0 (was 4.7), Symmetric Encryption 4.6 (was 4.3), IOStreams 2.0
  (was 1.9). No Rocket Job API changes; upgrade these gems before installing v7.

### Fixes

- Fix a one-second (one poll interval) delay between regular jobs. After completing a
  non-batch job a worker waited the full `Config.max_poll_seconds` before polling again,
  so a full queue drained at one job per poll interval per worker instead of as fast as
  `#perform` allowed. Workers now poll again immediately when work was performed, and only
  wait the full interval when no job is found. A completed batch job is likewise no longer
  delayed. Regression introduced in v5.2.0 (the "Worker refactor").
- Fix batch-job dequeue write contention that made large batch jobs progressively slower
  as workers scaled (observed ~5x: 10M records 18.7s -> 98.8s). Every worker was
  re-stamping the one running job document on every poll and claiming slices sorted by
  the global-minimum `_id`, so MongoDB serialized and retried the colliding writes.
  Joining an already-running batch job is now a read-only query (slice concurrency is
  already coordinated per-slice), and slice claims no longer force a global sort, letting
  concurrent claims land on different documents.

### New features

- Support Mongoid 9.0 / 9.1 and ActiveRecord 8.1.
- Add a pluggable event listener strategy, including a `:polling` mode that lets the
  Event/Subscriber pub-sub mechanism run without a tailable capped collection. This
  enables Rocket Job's cross-process shutdown/pause/log-level signaling on MongoDB-
  compatible stores that don't support capped collections, such as AWS DocumentDB.
  Configurable via `RocketJob::Event.listener_strategy`, `RocketJob::Event.poll_interval`, and
  `RocketJob::Event.event_retention_seconds`.
- Capture the reason a job is throttled and surface it in Mission Control. Throttles can
  now declare a `description:` (String or Proc); the triggered description is persisted
  on new `throttled_by`/`throttled_at` fields on both simple and batch jobs, and cleared
  automatically once the job is no longer throttled.

### Documentation

- Rewrite the documentation site: landing page, installation, Programmer's Guide, Batch
  Guide, Architecture and Internals (formerly "Advanced"), Included Jobs, Dirmon, and
  Mission Control (Web UI) pages, plus a new Upgrading guide and a rewritten README.
- Move the documentation site to the shared `rm-docs-theme` (the look and feel now lives
  in that theme, not in this repo), after an initial cosmic theme revamp, plus a
  reorganization of the Mission Control screenshots.
- Move the documentation site to `https://rocketjob.reidmorrison.com` and point all
  sister-project links at their `*.reidmorrison.com` doc sites. Repository links now
  reference the `main` branch.
- Add pages addressing MongoDB adoption objections (licensing and fit) and positioning
  compression/encryption as reasons to choose Rocket Job.
- Document inspecting and editing batch slices from the console, and add an event
  listener settings reference table.
- Add `CLAUDE.md` and expand `CONTRIBUTING.md` with an architecture guide.

### Internal

- Enforce RuboCop in the default Rake task and CI, and apply autocorrections.
- Substantially expand test coverage across the worker pool, supervisor, subscribers,
  events, batch categories, batch IO, sliced input queries, Dirmon, and built-in jobs.
- Remove the unused `RactorWorker` placeholder.
- Add an in-process batch benchmark harness (`rocketjob_batch_perf`) covering throughput,
  micro, and dequeue-contention modes, and move performance results into
  `docs/architecture.md`.
- Modernize CI: update dependency setup, make the JRuby matrix entry non-blocking, and
  bump `actions/checkout` to v7.

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
