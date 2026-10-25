---
layout: default
title: Batch Jobs Guide
mermaid: true
description: >-
  Jobs that process a large workload in parallel across many workers: uploading
  input, input and output categories, and reading tabular files.
---

**Contents**

* TOC
{:toc}

This guide covers batch jobs: jobs that process a large workload in parallel across many workers.
For the conventional single-worker job API (fields, scheduling, throttling, callbacks, queries), see
the [Programmer's Guide](guide.html).

## What is a batch job?

A regular [job](guide.html) runs on a single worker. A batch job breaks its input up into *slices*
so that many workers, often across hundreds of containers, process different parts of the work at
the same time.

Turn any job into a batch job by including `RocketJob::Batch` and writing a `perform` that handles a
single *record*:

~~~ruby
class ReverseJob < RocketJob::Job
  include RocketJob::Batch

  # Keep the job after it finishes so the output can be downloaded
  self.destroy_on_complete = false

  # Number of records per slice (the default)
  input_category slice_size: 100

  # Collect the value returned by each perform call as output
  output_category

  def perform(line)
    # Called once per record, spread across all available workers
    line.reverse
  end
end
~~~

A few terms:

* A **record** is one unit of work passed to `perform`. It is usually a line or row from a file, but
  can be any value that serializes to BSON (a String, Hash, Array, Integer, and so on).
* A **slice** is a group of records, 100 by default, that one worker claims and processes together.
* The job's input is uploaded into a dedicated MongoDB collection and divided into slices. For
  example, a 1,000,000 line file with the default `slice_size` of 100 becomes 10,000 slices.

Because the work is sliced, a batch job can be **paused, resumed, or aborted as a whole**, and if
any slices fail, all of them can be retried by retrying the job. A running batch job is also
**interrupted by a higher priority job**: low priority jobs use all available workers until more
important work arrives, then resume once it is done. See [Business Priority](guide.html#business-priority).

## Your first batch job

Using the `ReverseJob` above, queue some records for processing. The block form of `upload` hands you
a writer that you append records to one at a time:

~~~ruby
words = %w[these are some words to be processed across many workers]

job = ReverseJob.new
job.upload do |records|
  words.each do |word|
    records << word
  end
end
job.save!
~~~

Once the job completes, read the output (see [Collecting output](#collecting-output)):

~~~ruby
job.output.each do |slice|
  slice.each do |record|
    puts record
  end
end
~~~

## Uploading input data

Input data is uploaded into the job before it is saved. Rocket Job stores it in a MongoDB collection
unique to that job, and removes each slice as soon as it is processed. Failed slices stay in the
collection, marked as failed, holding the exception and the name of the worker that was processing
them.

Uploading the data into the job, rather than referencing an external file, has several benefits:

* Workers do not need shared access to the original file or data store.
* The file can be decompressed or decrypted once, up front, before it is sliced.
* No separate data store is needed to hold the job's input.
* Each slice has its own state, so it can fail independently and carry its own exception.

Data can be uploaded from a file, an Active Record query, a Mongoid query, an integer range, or a
block of code.

### Files

`upload` streams an entire file into the job, one record per line by default, and returns the number
of records uploaded. Very large files are streamed rather than loaded into memory, so files far
larger than RAM can be uploaded.

~~~ruby
job = ReverseJob.new
job.upload("myfile.txt")
job.save!
~~~

Rocket Job auto-detects compression and encryption from the file name and decodes it before slicing.
It has built-in support for:

* `Zip` files (add the `rubyzip` gem on CRuby; JRuby uses native Java Zip)
* `GZip` files
* files encrypted with [Symmetric Encryption](https://encryption.reidmorrison.com)
* delimited files (Windows CR/LF or Linux LF line endings, auto-detected)
* fixed-length record files

~~~ruby
# Auto-detected from the file extension:
job.upload("myfile.csv.zip")     # Zip
job.upload("myfile.csv.gz")      # GZip
job.upload("myfile.csv.zip.enc") # Encrypted Zip
~~~

Override the detected streams explicitly when the file name does not reflect the contents:

~~~ruby
job.upload("myfile.ze", streams: [:zip, :enc])
~~~

Useful `upload` keyword options:

| Option         | Description
|:---------------|:------------
| `category`     | Which input category to load into. Default: `:main`.
| `validate_rows` | `true` to parse each row of the file while it is uploaded, so that a file with a row that cannot be read is rejected before processing starts. Default: the input category's `validate_rows`. See [input categories](#input-categories).
| `file_name`    | Override the file name used to infer format and streams.

Files are read as UTF-8 text, since MongoDB only stores UTF-8 strings, and a UTF-8 byte order mark
at the start of the file (as Excel writes) is removed. A file that is not valid UTF-8 raises
`Encoding::UndefinedConversionError` and nothing is uploaded. For files in another encoding, set the
`encoding` of the input category, which converts their records to UTF-8:

~~~ruby
class LegacyImportJob < RocketJob::Job
  include RocketJob::Batch

  # The files that this job receives are saved by Excel on Windows.
  input_category format: :csv, encoding: "Windows-1252"
end
~~~

The category's encoding is saved with the job, so it also applies when a worker uploads the file, such
as a job started by [Dirmon](dirmon.html), or a `ConversionJob`. To read one file in another encoding,
set the encoding on the path instead, which takes the place of the category's:

~~~ruby
job.upload(IOStreams.path("legacy.csv").encoding("Windows-1252:UTF-8"))
~~~

Tabular formats, such as CSV, remove non-printable characters and characters that are not valid in
the file's encoding. A file in another encoding then loses those characters without any error, so when
its records must be complete, set the input category's `invalid_characters` to `:raise`, which fails the
upload with `IOStreams::Errors::InvalidEncoding`, naming the line of the first one, or to `:replace`,
which replaces each with `�` (U+FFFD) so that it can be seen in the record. Binary files cannot be
uploaded as records.

~~~ruby
input_category format: :csv, invalid_characters: :raise
~~~

Fixed width files are read as ASCII, as most are written by programs whose sizes count bytes, such as
those on a mainframe. A file with any other character raises `IOStreams::Errors::InvalidEncoding` and
nothing is uploaded, until its encoding is set: for example the input category's `encoding:
"ISO-8859-1"`, or `"IBM037"` for EBCDIC, or on the path, such as `encoding("UTF-8")` when its sizes count
UTF-8 characters, or `encoding(replace: " ")` to replace such characters with spaces. Non-printable
characters, such as NUL padding, are replaced with spaces so that the columns stay in place. Fixed width
output is downloaded as ASCII too, unless the output category's `encoding`, or the encoding of the
download path, is set.

A Zip stream must contain only one file; the first file found is loaded. CSV and other tabular
parsing is deliberately left to the workers (see [Reading tabular files](#reading-tabular-files)),
so by default a file is uploaded a raw line at a time.

For the full list of supported file types and transformations, see
[IOStreams](https://iostreams.reidmorrison.com).

### Active Record queries

`upload` uploads the result of an Active Record query, which
[IOStreams](https://iostreams.reidmorrison.com/queries) reads as one query that the database
streams, without building a model for each row. By default it uploads only the `:id` of each row:

~~~ruby
# Upload the ids of all US users
job.upload(User.where(country_code: "US"))
~~~

Supply column names to upload those columns instead of the id, as an Array per row, or the value
itself for a single column:

~~~ruby
job.upload(User.where(country_code: "US"), columns: %i[user_name zip_code])
~~~

In an input category with a `format`, such as CSV or JSON, the rows are uploaded in that format
instead, as a file of the query would hold them, after the names of the columns, by the category's
schema, otherwise by the types of the columns. `#perform` then receives each row as the rows of a file
in that format, such as a Hash of the columns:

~~~ruby
class ExportUsersJob < RocketJob::Job
  include RocketJob::Batch

  input_category format: :csv

  def perform(user)
    user["zip_code"]
  end
end

job = ExportUsersJob.new
job.upload(User.where(country_code: "US"), columns: %i[user_name zip_code])
~~~

The rows are uploaded in the order of the relation, and within its limit, and each column is read as
`pluck` reads it. The query is read on a connection of its own, so the pool of the model needs a
connection free besides that of the caller, and only the rows that were committed are uploaded,
not those that an open transaction of the caller wrote. The query stays open until every row is
uploaded, so upload a very large table in batches. A relation, and its batches, need Active Record
7.2 or later.

On JRuby, PostgreSQL, MySQL and SQLite stream a query with the adapters of AR-JDBC, see
[JRuby](https://iostreams.reidmorrison.com/queries#jruby). A database whose driver cannot stream a
query, such as MySQL with `trilogy`, raises `ArgumentError`. Upload the batches of the relation instead, which are read on the connection of the
caller. The batches upload the columns that the relation selects, so select them before
`in_batches`. Batches whose relation selects no columns raise `ArgumentError`, rather than upload
every column:

~~~ruby
job.upload(User.where(country_code: "US").select(:id).in_batches(of: 10_000))
~~~

To upload something other than the values of columns, such as what a method of the model returns,
write the records in a block, see [A block](#a-block):

~~~ruby
job.upload do |records|
  User.where(country_code: "US").find_each do |user|
    records << user.email.downcase
  end
end
~~~

### Mongoid queries

`upload` uploads the result of a MongoDB query too. It reads the collection directly, rather
than building a Mongoid model per document, to avoid that overhead:

~~~ruby
# Upload the ids of all users in Florida
job.upload(User.where(state: "FL"))

# Upload a field instead
job.upload(User.where(state: "FL"), columns: [:zip_code])
~~~

In an input category with a `format`, the fields are uploaded in that format, after their names, as
for an Active Record query.


### Integer ranges

A `Range` uploads a range of integers efficiently, which is ideal for driving work off a contiguous
range of ids. Each slice holds one `[first_id, last_id]` range of `slice_size` ids, and a descending
range processes the highest ids first:

~~~ruby
job.upload(1..1_000_000)
job.upload(1_000_000..1)
~~~

Each integer counts as one record in the job's `record_count`, so `percent_complete` follows the ranges
as they are processed.

`upload_arel`, `upload_mongo_query`, `upload_integer_range` and
`upload_integer_range_in_reverse_order`, which uploaded a query or a range before `upload` accepted
them, are removed in v8, see [Upgrading to v8](upgrading.html#removed).

### A block

When `upload` is given a block, it yields a writer to which records are appended one at a time:

~~~ruby
job.upload do |writer|
  10.times do |i|
    writer << i
  end
end
~~~

Each record must serialize to BSON (`Hash`, `Array`, `String`, `Integer`, `Float`, `Regexp`,
`Time`), and is read back as it is stored: a `Date` is stored as a `Time`, so it comes back as a
`Time`. Use a `String` rather than a `Symbol`, which MongoDB deprecated. With a `Hash`, keys must be
strings, not symbols.

For an input category with a `format` whose rows are lines of text, such as CSV or JSON, the block
writes the lines of a file: its header row first, when the file has one, then its rows. They are read as the lines of a file are, in slices
that each hold the header row. Writing anything other than a line, such as an `Array` of the values
of a row, or a `Hash`, raises `ArgumentError`: write each row as a line of the format, such as
`row.to_csv`, or upload it into a category without a `format`, which passes it to `perform` as it is. In the `:hash`
format, whose rows are Ruby objects, the block writes each record as a Hash instead, and in the `:array` format each
row as an Array, after an Array of the names of the columns, by which `perform` receives each row as a Hash. With a `schema`, a header row that does not match it raises
`IOStreams::Errors::InvalidHeader`, and nothing is uploaded:

~~~ruby
job.upload do |writer|
  writer << "name,age"
  writer << "Jack,21"
  writer << "Jill,22"
end
~~~

Text in a record must be UTF-8, since MongoDB only stores UTF-8. A string in another encoding, such as
ISO-8859-1 from a database connection, is converted, but a binary string, or one that is not valid
UTF-8, raises an `EncodingError` that names the number of the first such record, and nothing is
uploaded. Convert such text first, such as `text.encode("UTF-8", "Windows-1252")`.

The lines written into a category with a format are read as UTF-8 too: a line in another encoding is
converted, and the bytes of a binary line are read as UTF-8. Each character that is not valid in its
line's encoding is handled as the category's `invalid_characters` says. By default CSV and the other
tabular formats remove it, as they do from a file, while a fixed width format raises
`IOStreams::Errors::InvalidEncoding`. The error names the byte offset and line of the first one,
counting the header row, and nothing is uploaded. Non-printable characters other than line endings,
such as a tab or NUL, are removed as from a file too, or replaced with spaces in a fixed width format,
so that the columns stay in place.

## Input categories

The `input_category` class method configures how uploaded data is sliced and parsed. With no
arguments, a job has a single input category named `:main` with the defaults below.

~~~ruby
class MyJob < RocketJob::Job
  include RocketJob::Batch

  input_category slice_size: 500, serializer: :compress

  def perform(record)
    # ...
  end
end
~~~

Input category options:

| Option             | Default     | Description
|:-------------------|:------------|:------------
| `name`             | `:main`     | Name of the category. Use additional names for secondary input collections.
| `slice_size`       | `100`       | Number of records per slice.
| `serializer`       | `:compress` | Slice serialization: `:none`, `:compress`, or `:encrypt`. See [Compression and encryption](#compression-and-encryption).
| `format`           | `nil`       | Parse each record before `perform`: `nil` (raw line), `:auto`, or a tabular format such as `:csv`. See [Reading tabular files](#reading-tabular-files).
| `schema`           | `nil`       | The fields of each record and their types, and which columns a file can and must have. Also gives the position of each field of a `:fixed` file. See [Typed values with a schema](#typed-values-with-a-schema) and [Validating columns](#validating-columns).
| `encoding`         | `nil`       | The encoding of the files, such as `"Windows-1252"`, which is converted to UTF-8. `nil` reads UTF-8, or the format's own encoding, such as ASCII for `:fixed`. Name the byte order of UTF-16 or UTF-32, such as `"UTF-16LE"`. See [Files](#files).
| `invalid_characters` | `nil`     | What to do with a character that is not valid in the file's encoding, or in a line that the block of `upload` writes in the category's `format`: `:remove`, `:replace` with U+FFFD, or `:raise`. `nil` removes them from tabular formats, such as CSV, and raises for `:fixed` and lines.
| `validate_rows`    | `nil`       | Parse each row of a file in the category's `format` while it is uploaded, so that a file with a row that cannot be read is rejected before processing starts. Needs a `format`. A job, Dirmon entry or `UploadFileJob` that v7 saved with `mode: :hash` and a `format` is read with `validate_rows: true`.
| `columns`          | `nil`       | The header row of a file that Rocket Job 7 uploaded without a `schema`, which the workers read its lines by. Not set by v8, since each slice holds the header row of its file.

The options `allowed_columns`, `required_columns`, `skip_unknown` and `header_cleanser`, and setting
`columns` for a file without a header row, were removed in v8, since a `schema` replaces them, see
[Column options before v8](#column-options-before-v8).

A file in a `format`, such as CSV, is uploaded as its lines, in slices that each hold the header row
of the file, as it is in the file, and its format. Each worker reads the lines of its slice by that
header row, into the types of the fields of the `schema`, when there is one. Since the workers read
each slice with the category's `schema`, uploading a path that has another schema set on it raises
`ArgumentError`, also when the category has none.

By default the lines are uploaded as they are, which is the most performant, since each worker
parses its own lines. With `validate_rows: true`, each line is also parsed while the file is
uploaded, so that a file with a line that cannot be read, or with a value that is not valid for its
field, is rejected, and nothing is uploaded, before processing starts. The slices still hold the
lines. The rows are parsed one after another, so it is not recommended for very large files when
upload time matters:

~~~ruby
class ImportJob < RocketJob::Job
  include RocketJob::Batch

  input_category format: :csv, validate_rows: true

  def perform(row)
    # ...
  end
end
~~~

The `validate_rows` option of `upload` overrides the category's for that upload. It replaces the
`mode: :hash` of v7: a job, Dirmon entry or `UploadFileJob` that v7 saved with it, such as a
scheduled job, is read with `validate_rows: true` when its category has a `format`, see
[Upgrading to v8](upgrading.html#replace-the-hash-mode-with-validate_rows).
Only a file, and the lines that a block writes, are validated: a query or a range uploads values
rather than rows.

### More than one file

Each slice holds the header row of its file, so files can be uploaded into the same input category
one after another, in any mode, and the workers read the lines of each file by its own header row.
With a `schema`, the header row of each file is matched to the fields on its own, so with
`"fieldsMatch" => "equal"` the files can even list their columns in different orders.

When an upload fails, such as when the file cannot be read to its end, its records are not kept, so
the job can upload the file again when it is retried. The records of the files uploaded before it
are kept.

When a batch job restarts, such as the next run of a scheduled job, its input categories keep their
settings, and each run reads the header row of its own file.

## Collecting output

To keep the value returned by `perform`, register an output category with `output_category`. With no
arguments it registers a single output category named `:main`:

~~~ruby
class ReverseJob < RocketJob::Job
  include RocketJob::Batch

  self.destroy_on_complete = false

  output_category

  def perform(line)
    line.reverse
  end
end
~~~

Read the collected output once the job has completed:

~~~ruby
job.output.each do |slice|
  slice.each do |record|
    puts record
  end
end
~~~

Or download it straight to a file, optionally compressed on the way out:

~~~ruby
job.download("reversed.txt.gz")
~~~

### Output ordering

The output slices and records are in exactly the same order as the records were uploaded, which
makes it easy to line an output record up with its input record. Two things change that alignment:

* An input file with a header row (for example CSV) whose output format does not have one (for
  example JSON) shifts every output record by one line.
* Setting `nils: false` on the output category (the default) skips records for which `perform`
  returned `nil`, so those positions are absent from the output.

### Waiting for completion

Output can be queried at any time, but it is only complete once the job has finished. To wait
programmatically:

~~~ruby
loop do
  sleep 1
  job.reload
  break unless job.running? || job.queued?
end
~~~

### Output categories

The `output_category` class method accepts these options:

| Option           | Default     | Description
|:-----------------|:------------|:------------
| `name`           | `:main`     | Name of the category. Register additional names for [multiple output files](#multiple-output-files).
| `serializer`     | `:compress` | Slice serialization: `:none`, `:compress`, `:encrypt`, `:bz2`, or `:encrypted_bz2`. See [Fast bzip2 output files](#fast-bzip2-output-files).
| `format`         | `nil`       | Render each result: `nil`, `:auto`, or a tabular format such as `:csv`. See [Writing tabular files](#writing-tabular-files).
| `schema`         | `nil`       | The fields that are written, in order, and their types. Also gives the position of each field of a `:fixed` file. See [Typed values with a schema](#typed-values-with-a-schema) and [Writing tabular files](#writing-tabular-files).
| `encoding`       | `nil`       | The encoding to write the file in, such as `"ISO-8859-1"`. `nil` writes UTF-8, or the format's own encoding, such as ASCII for `:fixed`. Name the byte order of UTF-16 or UTF-32, such as `"UTF-16LE"`.
| `nils`           | `false`     | When `true`, store `nil` results too; when `false`, skip them.

A `:csv`, `:psv` or `:fixed` output category needs a `schema`, whose fields are the columns that it
writes, in order. The `columns` option, which listed the columns to write, was removed in v8, since
the `schema` replaces it, see [Filtering output columns](#filtering-output-columns).

### Multiple output files

A single batch job can write several output files by registering more than one output category and
returning categorized results from `perform`.

Use `RocketJob::Batch::Result` to direct a single value to a named category, and
`RocketJob::Batch::Results` to return several at once. `Result.new` takes the **category first, then
the value**:

~~~ruby
class MultiFileJob < RocketJob::Job
  include RocketJob::Batch

  self.destroy_on_complete = false

  # Default :main output category, plus an :invalid category
  output_category
  output_category(name: :invalid)

  def perform(line)
    if line.length < 10
      # Send short lines to the :invalid output collection
      RocketJob::Batch::Result.new(:invalid, line)
    else
      # Plain return values go to the :main output collection
      line.reverse
    end
  end
end
~~~

Download each category to its own file:

~~~ruby
job.download("reversed.txt.gz")
job.download("invalid.txt.gz", category: :invalid)
~~~

To write to several categories from a single `perform` call, collect them in a `Results`:

~~~ruby
def perform(row)
  outputs = RocketJob::Batch::Results.new
  outputs << {name: row["name"], age: row["age"]}                         # goes to :main
  outputs << RocketJob::Batch::Result.new(:zip_codes, {zip: row["zip"]})  # goes to :zip_codes
  outputs
end
~~~

## Reading tabular files

Received data is often tabular, like a spreadsheet, with a header row describing each column (CSV,
PSV, Excel, and so on). Set `format` on the `input_category` and Rocket Job parses each row just
before `perform` is called, passing in a `Hash` of header name to value instead of the raw line:

~~~ruby
class TabularJob < RocketJob::Job
  include RocketJob::Batch

  input_category format: :csv

  def perform(record)
    # record is a Hash, for example:
    # { "first_field" => 100, "second" => 200, "third" => 300 }
  end
end
~~~

~~~ruby
job = TabularJob.new
job.upload("my_really_big_csv_file.csv")
job.save!
~~~

CSV parsing is left to the workers, so the file still uploads a line at a time with minimal memory
overhead, even for very large files.

### Auto-detecting the file type

Set `format: :auto` to detect the format from the upload file name. The same unchanged job can then
process CSV, PSV, JSON, or xlsx files, as long as the column headers match:

~~~ruby
class TabularJob < RocketJob::Job
  include RocketJob::Batch

  input_category format: :auto

  def perform(record)
    # record is a Hash of header name => value
  end
end
~~~

~~~ruby
csv_job = TabularJob.new
csv_job.upload("really_big.csv")
csv_job.save!

excel_job = TabularJob.new
excel_job.upload("really_big.xlsx")
excel_job.save!

json_job = TabularJob.new
json_job.upload("really_big.json")
json_job.save!
~~~

### Typed values with a schema

Set `schema` on a category to read each value as its type, instead of as text. A schema is a
[Frictionless Table Schema](https://datapackage.org/standard/table-schema/) that lists each field and
its type, such as `integer`, `number` (a `BigDecimal`), `date`, `datetime` or `boolean`. IOStreams
reads and writes it, see [Schema](https://iostreams.reidmorrison.com/formats.html#schema).

~~~ruby
class PeopleJob < RocketJob::Job
  include RocketJob::Batch

  input_category format: :csv,
                 schema: {
                   "fields" => [
                     {"name" => "name", "type" => "string"},
                     {"name" => "age", "type" => "integer"},
                     {"name" => "balance", "type" => "number"},
                     {"name" => "joined", "type" => "date"}
                   ]
                 }

  def perform(record)
    # record is a Hash of typed values, for example:
    # { "name" => "Jack", "age" => 21, "balance" => BigDecimal("12.5"), "joined" => Date.new(2026, 10, 13) }
  end
end
~~~

A value that is not of its type, such as `N/A` in an `integer` field, fails its record with
`IOStreams::Errors::InvalidValue`.

The schema also describes the file:

* **Fixed width files** need a schema, since it gives the `width` of each field:

  ~~~ruby
  input_category format: :fixed,
                 schema: {
                   "fields" => [
                     {"name" => "name", "type" => "string", "width" => 10},
                     {"name" => "zip", "type" => "integer", "width" => 5}
                   ]
                 }
  ~~~

* **A file without a header row** is described with `"header" => false`: its columns are the fields,
  in order.
* **A schema kept in a file** is set as the path or url of its JSON, such as
  `schema: "s3://bucket/schemas/people.json"`. It is read when the category is first used, so the file
  must be available to every server that runs the job.

In every upload mode the slices hold the lines of the file as they are, and the workers read each
value into the type of its field, so a `date` reaches `perform` as a `Date`.

### Validating columns

The schema also says which columns a file can have and must have, so that a file with unexpected
columns is rejected before any worker runs. Each column of the header row is matched to a field by its
name, or one of its `aliases`, whatever its case, spaces and punctuation, so `First Name`, `first_name`
and `FIRST.NAME` are the same column. The keys of each record are the names of the fields, however
the file names its columns.

`fieldsMatch` says which columns a file can have:

| `fieldsMatch` | The columns of the file
|:--------------|:-----------------------
| `"exact"`     | Are the fields, in the same order. The default.
| `"equal"`     | Are the fields, in any order.
| `"subset"`    | Include every field. Other columns are skipped.
| `"superset"`  | Are all fields, but a field can be missing.
| `"partial"`   | Include at least one field. Other columns are skipped.

A field with `"constraints" => {"required" => true}` must be one of the columns, whatever the
`fieldsMatch`, and must have a value in every record:

~~~ruby
input_category format: :csv,
               schema: {
                 "fieldsMatch" => "partial",
                 "fields"      => [
                   {"name" => "login", "constraints" => {"required" => true}},
                   {"name" => "last_login", "type" => "datetime"},
                   {"name" => "name"},
                   {"name" => "state", "aliases" => ["Province", "Region"]}
                 ]
               }
~~~

Columns that do not match the schema raise `IOStreams::Errors::InvalidHeader`:

* A header row is checked during upload, so a malformed file is rejected, and nothing is uploaded,
  before any worker runs.
* A format without a header row, such as JSON, supplies the keys of each record, so they are matched
  and checked as each record is processed. With `format: :auto` the schema therefore still applies
  when a `.csv` file is renamed to `.json`.
* A column that could be either of two fields, or two columns that are the same field, such as `id`
  and `ID`, also raise, rather than one value silently replacing the other.

#### Column options before v8

Before v8 the columns of an input category were described with the options below, which v7.1
deprecates, and v8 removed, see [Upgrading to v8](upgrading.html#the-deprecated-category-options-are-removed).
The schema property that replaces each one:

| Option                                      | With a schema
|:--------------------------------------------|:-------------
| `columns`, for a file without a header row  | The fields are the columns, in order, with `"header" => false`.
| `allowed_columns`                           | `"fieldsMatch" => "superset"`, which accepts a file without some of the fields, as `allowed_columns` does, or `"equal"` when `required_columns` lists every allowed column.
| `allowed_columns` with `skip_unknown: true` | `"fieldsMatch" => "partial"`, which accepts a file without some of the fields, as `allowed_columns` does, or `"subset"` when `required_columns` lists every allowed column.
| `required_columns`                          | `"constraints" => {"required" => true}` with `"allowBlank" => true` on each field, which needs the column but not a value, as `required_columns` did. Without `allowBlank`, a blank value raises too.
| `header_cleanser`                           | Not needed: the keys of each record are the names of the fields, which the columns are matched to.

The restrictions were compared to the column names after they were cleansed, or as they were with
`header_cleanser: :none`, and the keys of each record were the cleansed column names. So to keep the
keys that a job reads, name each field as the column was cleansed, which is how `allowed_columns` and
`required_columns` already named them, such as `last_login` for the column `Last Login`: the schema
matches the column to that field.

## Writing tabular files

To produce a tabular output file, set `format` on the `output_category` and return a `Hash` from
`perform`. Rocket Job renders each hash into a line of the chosen format, and writes the header row
automatically:

~~~ruby
class ExportUsersJob < RocketJob::Job
  include RocketJob::Batch

  # These fields are written, in this order
  output_category format: :csv,
                  schema: {
                    "fields" => [
                      {"name" => "login"},
                      {"name" => "last_login", "type" => "datetime"}
                    ]
                  }

  def perform(id)
    u = User.find(id)
    {"login" => u.login, "last_login" => u.updated_at}
  end
end
~~~

~~~ruby
job = ExportUsersJob.new
job.upload(User.where(locked: true))
job.save!
# ... once complete ...
job.download("output.csv")
~~~

Sample `output.csv`:

~~~csv
login,last_login
jbloggs,2019-02-11T05:43:20Z
kadams,2019-01-12T01:20:20Z
~~~

The header row is the names of the fields. The keys of each hash are matched to the fields the same
way as the columns of an input file, so a hash keyed `"Login"`, or by the Symbol `:login`, writes the
`login` field too.

### Filtering output columns

By default a key that is not a field of the schema raises `IOStreams::Errors::InvalidHeader`, so a
misspelled key is not silently left out. With `"fieldsMatch" => "subset"` the other keys are skipped
instead, so `perform` can return a full attribute hash and let the category select which fields to
export. The same job can then export different fields on different runs:

~~~ruby
class ExportUsersJob < RocketJob::Job
  include RocketJob::Batch

  output_category format: :csv,
                  schema: {
                    "fieldsMatch" => "subset",
                    "fields"      => [
                      {"name" => "login"},
                      {"name" => "last_login", "type" => "datetime"}
                    ]
                  }

  def perform(login)
    # Return all attributes; only the fields of the schema are written
    User.find_by(login: login).attributes
  end
end
~~~

Override the schema per instance to widen or narrow the export:

~~~ruby
job = ExportUsersJob.new
job.output_category.schema = {
  "fieldsMatch" => "subset",
  "fields"      => [
    {"name" => "login"},
    {"name" => "last_login"},
    {"name" => "name"},
    {"name" => "state"}
  ]
}
job.save!
~~~

An output category's `columns`, which listed the columns to write before v8, were removed in v8: name
those columns as the fields of its schema instead.

### Single output file via after_batch

The `after_batch` callback runs once, after all slices finish, which is a natural place to download
the assembled output file. This job parses a CSV input and writes a single CSV output:

~~~ruby
class TransformJob < RocketJob::Job
  include RocketJob::Batch

  self.destroy_on_complete = false

  input_category  format: :csv
  output_category format: :csv

  after_batch :download_file

  def perform(row)
    {
      name: "#{row['first_name'].downcase} #{row['last_name'].downcase}",
      age:  row["age"]
    }
  end

  def download_file
    download("names.csv")
  end
end
~~~

## Compression and encryption

Each category has a `serializer` that controls how its slices are stored. Compression reduces network
and disk usage, and is recommended for large jobs. As of Rocket Job v6 the default serializer is
`:compress`; set it to `:none` to disable. Encryption is opt-in and configured per job: setting the
serializer to `:encrypt` keeps that job's slices protected at rest, which helps meet compliance
requirements, without any change to your `#perform` code.

~~~ruby
class ReverseJob < RocketJob::Job
  include RocketJob::Batch

  input_category  serializer: :compress
  output_category serializer: :compress

  def perform(line)
    line.reverse
  end
end
~~~

Set the serializer to `:encrypt` to encrypt slices at rest with
[Symmetric Encryption](https://encryption.reidmorrison.com). Data is compressed
before being encrypted, to reduce the volume encrypted:

~~~ruby
input_category  serializer: :encrypt
output_category serializer: :encrypt
~~~

### Fast bzip2 output files

Compressing a large output file with bzip2 is slow, and `download` runs on a single thread, so
compressing the whole file as it is written can take longer than processing the job did. The `:bz2`
and `:encrypted_bz2` output serializers move that work to the workers instead:

* Each worker bzip2-compresses its own slice when it saves the output, so compression runs in
  parallel across every worker processing the job.
* `download` does not decompress the slices and compress them again. It writes each slice's
  compressed data directly to the output file. With `:encrypted_bz2` it only decrypts each slice
  first; with `:bz2` it copies the slice as is.

`:encrypted_bz2` also keeps the output encrypted at rest in MongoDB, like `:encrypt`, until it is
downloaded. The downloaded file itself is bzip2 compressed, not encrypted.

~~~ruby
class ExportJob < RocketJob::Job
  include RocketJob::Batch

  self.destroy_on_complete = false

  input_category  format: :csv
  output_category format:     :csv,
                  schema:     {
                    "fields" => [
                      {"name" => "name"},
                      {"name" => "age", "type" => "integer"}
                    ]
                  },
                  serializer: :encrypted_bz2

  after_batch :download_file

  def perform(row)
    {"name" => "#{row['first_name']} #{row['last_name']}", "age" => row["age"]}
  end

  def download_file
    download("export.csv.bz2")
  end
end
~~~

Things to know:

* The output file name must end in `.bz2`. `download` uses the file name to recognize that the
  file is bzip2 compressed, and writes the already compressed slices into it.
* A header line, such as the CSV header row above, is compressed and written at the start of the file.
* The text is written in the output category's `encoding`, or the format's own, such as ASCII for
  fixed width, since it is converted before it is compressed. A character that the encoding does not
  have fails the slice when it is processed. An encoding cannot be set on the download path.
* The output file is a series of bzip2 streams, at least one per slice, which the bzip2 format allows. The
  `bzip2` command line utility, and most tools built on libbzip2, read every stream. Some other
  implementations stop after the first stream and return only the first slice, so check that the
  system receiving the file reads multi-stream bzip2 files.
* Records are separated with a newline (`"\n"`); the record delimiter cannot be changed.
* The return value of `download` is the number of slices written, not the number of records.
* Downloading with a block yields the header line, if any, as text, followed by each slice's
  compressed data rather than the individual records.

### PGP encrypted output files

When exchanging files with another system, an open standard like PGP is ideal. Because `download`
accepts an [IOStreams](https://iostreams.reidmorrison.com) path, the output file can be PGP
encrypted for a recipient on the way out:

~~~ruby
class ExportJob < RocketJob::Job
  include RocketJob::Batch

  self.destroy_on_complete = false

  input_category  format: :csv
  output_category format: :csv

  field :pgp_public_key, type: String
  validates_presence_of :pgp_public_key

  after_batch :download_file

  def perform(row)
    {name: "#{row['first_name']} #{row['last_name']}", age: row["age"]}
  end

  def download_file
    path = IOStreams.path("names.csv")
    path.option(:pgp, import_and_trust_key: pgp_public_key)
    download(path)
  end
end
~~~

## Throttling concurrent workers

`throttle_running_workers` limits how many workers process slices of a single batch job instance at
once. Use it when too many concurrent workers would overwhelm a third party system or write too much
data too quickly to a primary database. It also lets several batch jobs run concurrently rather than
one job consuming every worker.

~~~ruby
class ReverseJob < RocketJob::Job
  include RocketJob::Batch

  # No more than 10 workers on this job at a time
  self.throttle_running_workers = 10

  def perform(line)
    line.reverse
  end
end
~~~

This value can be changed at any time, even while the job runs, to raise or lower the worker count.
It is a soft limit: the number of active workers may briefly exceed or dip below it. `0` or `nil`
means no limit (the default).

### Custom batch throttles

Define custom throttles for batch jobs with `define_batch_throttle`. The named method receives the
slice and returns true when the throttle is exceeded, in which case the slice is left for later:

~~~ruby
class MyJob < RocketJob::Job
  include RocketJob::Batch

  # Do not process slices when the MySQL replica delay exceeds 5 minutes
  define_batch_throttle :mysql_throttle_exceeded?

  def perform(record)
    # ...
  end

  private

  def mysql_throttle_exceeded?(slice)
    status        = ActiveRecord::Base.connection.select_one("show slave status")
    seconds_delay = Hash(status)["Seconds_Behind_Master"].to_i
    seconds_delay >= 300
  end
end
~~~

As with simple jobs, pass a `description:` (a String, or a Proc receiving the job and slice) to set
the reason shown in Mission Control while slices are throttled. It is recorded on the job in
`throttled_by` and cleared once slices resume processing.

### Processing windows

`RocketJob::Batch::ThrottleWindows` restricts when slices may be processed, which is useful for a
long-running job that should only run outside business hours. It supports up to two windows. The
windows only gate slice processing; the job can still start and finish at any time.

~~~ruby
class AfterHoursJob < RocketJob::Job
  include RocketJob::Batch
  include RocketJob::Batch::ThrottleWindows

  # Monday to Thursday, slices may run from 5pm Eastern for 15 hours (until 8am)
  self.primary_schedule = "0 17 * * 1-4 America/New_York"
  self.primary_duration = 15.hours

  # All weekend, starting Friday 5pm Eastern for 63 hours (until 8am Monday)
  self.secondary_schedule = "0 17 * * 5 America/New_York"
  self.secondary_duration = 63.hours

  def perform(record)
    # ...
  end
end
~~~

### Lowering priority for large jobs

`RocketJob::Batch::LowerPriority` automatically lowers a job's priority based on its `record_count`,
so that large jobs yield to smaller ones. Add `:lower_priority` as a `before_batch`, after the
`record_count` has been set (that is, after the data has been uploaded):

~~~ruby
class SampleJob < RocketJob::Job
  include RocketJob::Batch
  include RocketJob::Batch::LowerPriority

  before_batch :upload_data, :lower_priority

  def perform(record)
    record.reverse
  end

  private

  def upload_data
    upload do |stream|
      %w[abc def ghi].each do |record|
        stream << record
      end
    end
  end
end
~~~

## Record and line numbers

While a record is processed, `rocket_job_record_number` is its number in its upload, from 1, without
the header row of its file, so that a blank row counts too. For the rows of a file,
`rocket_job_line_number` is the line of the file that the record starts on, as a text editor numbers
it, so the header row, and each line of a quoted value with line breaks, count too. It is nil for
records that are not the lines of a file, such as those of a query or a Parquet file:

~~~ruby
class ImportJob < RocketJob::Job
  include RocketJob::Batch

  input_category format: :csv

  def perform(row)
    return if row.nil?

    logger.info("Record #{rocket_job_record_number} is on line #{rocket_job_line_number}")
  end
end
~~~

Each log entry written while a record is processed is tagged with its `record`, and its `line` when it
has one, so that support staff can find the row in its file.

A slice answers the same numbers for each of its records, counting from 0, such as to find the row of a
failed record:

~~~ruby
slice = job.input.failed.first
index = slice.processing_record_number - 1

slice.record_number_at(index)   # => 1205
slice.line_number_at(index)     # => 1207
~~~

The rows of a file keep their numbers when a record is replaced or removed, see
[Editing and retrying failed records](#editing-and-retrying-failed-records).

## Error handling

Because a batch job is made of many slices, individual records can fail while others keep processing.
Inspect the exceptions on failed slices:

~~~ruby
job = RocketJob::Job.find("55bbce6b498e76424fa103e8")
job.input.each_failed_record do |record, slice|
  p slice.exception
end
~~~

Once every slice has either completed or failed, and only failed slices remain, the job as a whole is
marked `failed`. Retrying the job retries only the failed slices, so successfully processed records
are not reprocessed.

## Inspecting slices from the console

The slices that make up a batch job are ordinary MongoDB documents, so a running or failed job can be
inspected directly from a Rails (or `irb`) console. `job.input` returns the input slice collection and
`job.output` (when the job collects output) returns the output slice collection. Both respond to the
same set of query and enumeration methods.

**Counting slices.** `count` returns the total number of slices, and each state has its own scope
(`queued`, `running`, `failed`, `completed`) that can be counted or iterated:

~~~ruby
job = RocketJob::Job.find("55bbce6b498e76424fa103e8")

job.input.count           # Total number of input slices
job.input.failed.count    # Number of failed slices
job.input.running.count   # Slices currently being processed
job.input.queued.count    # Slices still waiting to be processed
~~~

**Fetching slices.** The state scopes, together with `first`, `last`, `each`, `where`, and the standard
`Enumerable` methods, return individual slices. `first`/`last` are sorted by `_id`, which is usually the
order in which the data was uploaded:

~~~ruby
job.input.failed.first            # First failed slice
job.input.first                   # First input slice, in upload order

# Iterate over every failed slice and print its exception class:
job.input.failed.each do |slice|
  puts slice.exception.class_name
end
~~~

**Reading records within a slice.** A slice is read like an array of its records, with `each`, `to_a`
and the other `Enumerable` methods, and carries metadata about how it was processed. A slice of the
rows of a file holds them in an `IOStreams::Slice` rather than an Array, so read them through the slice
rather than through `slice.records`:

~~~ruby
slice = job.input.failed.first

slice.to_a                        # Array of records in this slice
slice.size                        # Number of records in the slice
slice.first_record_number         # Record number of the first record in its upload
slice.failure_count               # How many times this slice has failed
slice.worker_name                 # Worker that last processed the slice
slice.failed_record               # The specific record that raised the exception
~~~

**Inspecting the exception.** A failed slice embeds a `RocketJob::JobException` on `slice.exception`
exposing `class_name`, `message`, `backtrace`, and `worker_name`:

~~~ruby
exception = job.input.failed.first.exception
exception.class_name              # e.g. "RuntimeError"
exception.message
exception.backtrace
~~~

**Summarizing failures.** For a large job with many failed slices, `group_exceptions` aggregates the
failures by exception class, returning the count and the unique messages for each class. This is the
fastest way to see _what_ is failing without paging through slices one at a time:

~~~ruby
job.input.group_exceptions.each do |summary|
  puts "#{summary.class_name}: #{summary.count}"
  summary.messages.each do |message|
    puts "  #{message}"
  end
end
~~~

All of the above work equally on `job.output` for jobs that collect output, and on named categories via
`job.input(:category_name)` / `job.output(:category_name)`.

## Editing and retrying failed records

Sometimes a slice fails because of bad data rather than a code bug. Rather than fixing the source file
and re-uploading the whole job, the offending record can be corrected directly on the slice and the job
retried. Change a record with `replace_record` or remove one with `delete_record`, and saving the
slice persists the edited records. Both keep the line and record number of each row of a file, see
[Record and line numbers](#record-and-line-numbers).

**Example: correct the failed record and retry the job.**
`failed_record` returns the record that raised the exception, and `processing_record_number` is its
(1-based) position within the slice:

~~~ruby
job   = RocketJob::Job.find("55bbce6b498e76424fa103e8")
slice = job.input.failed.first

slice.failed_record               # => "12345,,Jack"  (missing middle field)

# Replace the record that failed.
index = slice.processing_record_number - 1
slice.replace_record(index, "12345,A,Jack")
slice.save!

# Retry the job: every failed slice is requeued and reprocessed.
job.retry!
~~~

On retry each slice resumes from `processing_record_number`, so records that already completed
successfully within the slice are not reprocessed. The corrected record is the next one processed.

**Example: fix every record in a slice.**
Assigning an Array to `records` replaces them all, and is persisted by `save!`. The rows of a file
keep the header row of their file, but not the line and record number of each row, which then count
from `first_record_number`:

~~~ruby
slice         = job.input.failed.first
slice.records = slice.map(&:strip)   # Clean up all records in the slice
slice.save!

job.retry!
~~~

**Example: retry a single slice that failed while the job is still running.**
While a job is still `running` (some slices failed but others are still processing), an individual slice
can be edited and requeued on its own without retrying the whole job. An active worker picks it up:

~~~ruby
slice = job.input.failed.first
slice.replace_record(0, "corrected value")
slice.save!

slice.retry!   # Move just this slice from failed back to queued
~~~

Note that workers only process slices for a job that is in the `running` state. Once all slices have
finished and only failed slices remain, the job itself transitions to `failed`, and `slice.retry!`
alone will not reprocess it. In that case use `job.retry!`, which returns the job to `running` and
requeues all of its failed slices.

## Batch callbacks

In addition to the standard [job callbacks](guide.html#callbacks), batch jobs add callbacks at the
slice and batch level:

* `before_slice`, `after_slice`, `around_slice`: run on the worker, around each slice.
* `before_batch`, `after_batch`: run once for the whole job. They run asynchronously. `around_batch`
  is not supported.

`before_batch` is the place to upload data, and `after_batch` the place to download results or do
final bookkeeping, as shown in the [single output file](#single-output-file-via-after_batch) and
[lower priority](#lowering-priority-for-large-jobs) examples.

A job that fails, or whose server dies, while its `before_batch` callbacks run, runs them again when
it is retried or requeued. Before they run again, the job removes the slices that they uploaded, and
puts back the `record_count` and the input categories as they were when the callbacks started,
including the header row that an upload read. So uploading in `before_batch` does not duplicate the
input, and slices uploaded before the job started are kept.

## Gathering statistics

`RocketJob::Batch::Statistics` lets a job count things while it runs and have those counts aggregated
across every slice and worker. It is the standard way to answer "how many records were valid, invalid,
or skipped?" without adding your own fields or a separate datastore.

Add the plugin and call `statistics_inc` inside `perform`:

~~~ruby
class ImportJob < RocketJob::Job
  include RocketJob::Batch
  include RocketJob::Batch::Statistics

  def perform(row)
    if row["email"].blank?
      statistics_inc("invalid")
      return
    end

    statistics_inc("imported")
    # ... import the row ...
  end
end
~~~

When the job completes, the totals are available in the `statistics` hash field:

~~~ruby
job.reload.statistics
# => {"imported" => 9_840, "invalid" => 160}
~~~

The counts are also included in the job's log entry when it completes or fails.

Increment by more than one by passing an amount, and increment several counters at once by passing a
hash:

~~~ruby
statistics_inc("rows", row.size)
statistics_inc("invalid" => 1, "skipped" => 1)
~~~

Keys may use dot notation to build nested counts, which is handy for grouping related categories:

~~~ruby
statistics_inc("invalid.missing_email")
statistics_inc("invalid.bad_country")
# => {"invalid" => {"missing_email" => 12, "bad_country" => 4}}
~~~

Statistics are committed per slice using an atomic MongoDB `$inc`, so thousands of workers can update
the same counters concurrently. Counts are gathered while a slice is processed and only saved for
records that complete successfully: if a `perform` raises an exception, the increments from that record
are discarded, so retrying a failed slice does not double-count.

The built-in [`OnDemandBatchJob`](jobs.html#on-demand-batch-job) already includes this plugin, so
`statistics_inc` is available in its `code` without any extra setup.

## Batch fields and status

Including `RocketJob::Batch` adds these fields:

| Field          | Description
|:---------------|:------------
| `record_count` | Total number of input records. Set automatically by `upload`. Until it is set, workers process slices but do not complete the job, which allows processing to begin while data is still uploading.
| `sub_state`    | Read-only. Breaks the `running` state into `:before`, `:processing`, `:after`, and `:complete`.

`percent_complete`, `worker_count`, and `worker_names` are all batch-aware. The `status` hash adds
slice-level counts (`queued_slices`, `active_slices`, `failed_slices`, `output_slices`) and, while
running, an estimated remaining duration:

~~~ruby
job.reload
job.status
# => {"active_slices" => 8, "failed_slices" => 0, "queued_slices" => 1200, ... }
~~~

## The batch job lifecycle

A batch job uses the same top-level states as a [simple job](guide.html#the-job-lifecycle)
(`queued`, `running`, `completed`, `failed`, `paused`, `aborted`), but the `running` state is broken
into `sub_state` phases so that the one-time `before_batch` / `after_batch` work is coordinated
separately from the many slices processed in parallel:

~~~mermaid
stateDiagram-v2
    [*] --> queued : create / upload
    queued --> running : start

    state running {
        [*] --> before : sub_state
        before --> processing : before_batch done
        processing --> after : all slices done
        after --> [*]
    }

    running --> completed : complete
    completed --> [*]

    running --> failed : a slice (or callback) fails
    failed --> queued : retry (was in before_batch)
    failed --> running : retry (re-run failed slices / after_batch)

    queued --> paused : pause
    running --> paused : pause (only during processing)
    paused --> running : resume

    running --> queued : requeue (worker died, in before_batch)
    running --> running : requeue (worker died, processing / after_batch)

    queued --> aborted : abort
    running --> aborted : abort
    failed --> aborted : abort
    paused --> aborted : abort
    aborted --> [*]
~~~

The three `running` sub-states, exposed on the read-only `sub_state` field:

* **`before`**: the job has started and its `before_batch` callbacks are running on a single worker.
  This is where input is typically uploaded.
* **`processing`**: slices are being claimed and processed concurrently by many workers. This is the
  only sub-state in which a batch job is [pausable](#throttling-concurrent-workers).
* **`after`**: every slice has finished, and the `after_batch` callbacks are running on a single
  worker (downloading results, final bookkeeping). `complete` then clears `sub_state` and moves the
  job to `completed`.

How batch jobs differ from simple jobs in this diagram:

* **`fail`**: if any slice raises and only failed slices remain, the job as a whole becomes `failed`
  (see [Error handling](#error-handling)). Individual slices carry their own state and exceptions.
* **`retry`** is sub-state aware: a job that failed during `before_batch` retries back to `queued`,
  without what `before_batch` uploaded (see [Batch callbacks](#batch-callbacks)), while one that
  failed during or after processing retries straight to `running` and reprocesses only the failed
  slices, leaving already-completed records untouched.
* **`requeue`** (automatic when a worker's server dies) also depends on sub-state: work interrupted
  during `before_batch` goes back to `queued`, also without what it uploaded; work interrupted during processing or `after_batch` is
  requeued within `running` so the running slices are reclaimed by other workers.

As with simple jobs, each transition is callable on the job and comes in two forms: `job.abort`
changes the state in memory only (call `job.save!` to persist), while `job.abort!` transitions and
saves in one step. See [Triggering a transition](guide.html#triggering-a-transition).

## How batch jobs work

A batch job's input is uploaded into a MongoDB collection dedicated to that job and split into
slices. Each slice is an independent unit of work that any worker can claim with an atomic operation,
so thousands of workers across many servers process slices concurrently without colliding:

~~~mermaid
flowchart LR
    input["input file"] --> slices["slices"]
    slices --> worker1["worker"]
    slices --> worker2["worker"]
    slices --> workerN["worker"]
    worker1 -- slice 1 --> output["output collection"]
    worker2 -- slice 2 --> output
    workerN -- slice N --> output
    output --> download["download"]
~~~

Slices live in a separate MongoDB client (`rocketjob_slices`) from the jobs themselves. MongoDB's
ability to spill from memory to disk is what lets a single job hold millions of input and output
records without exhausting memory or needing a separate data store. Each slice carries its own state,
so a failure is isolated to that slice, retains its exception, and can be retried on its own.

## Next steps

* [Programmer's Guide](guide.html): the core job API that batch jobs build on.
* [Dirmon](dirmon.html): trigger batch jobs automatically when files arrive.
* [Mission Control](mission_control.html): watch slices and jobs run, and retry, pause, or abort them.
* [Included Jobs](jobs.html): ready-to-use jobs such as `OnDemandBatchJob`.
