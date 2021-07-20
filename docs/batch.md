---
layout: default
---

# Rocket Job Batch Programmers Guide

#### Table of Contents

* [Batch Jobs](#batch-jobs)
* [Batch Output](#batch-output)
* [Batch Job Throttling](#batch-job-throttling)
* [Large File Processing](#large-file-processing)
* [Multiple Output Files](#multiple-output-files)
* [Error Handling](#error-handling)
* [Reading Tabular Files](#reading-tabular-files)
* [Writing Tabular Files](#writing-tabular-files)

## Batch Jobs

Regular jobs run on a single worker. In order to scale up and use all available workers
it is necessary to break up the input data into "slices" so that different parts of the job
can be processed in parallel.

Jobs that include `RocketJob::Batch` break their work up into slices so that many workers can work
on the individual slices at the same time. Slices take a large and unwieldy job and break it up
into _bite-size_ pieces that can be processed a slice at a time by the workers.

Since batch jobs consist of lots of smaller slices the job can be paused, resumed, or even aborted as a whole.
If there are any failed slices when the job finishes, they can all be retried by retrying the job itself.

For example, using the default `slice_size` of 100, and the uploaded file contains 1,000,000 lines,
then the job will contain 10,000 slices.

Slices are made up of records, 100 by default, each record usually refers to a line or row in a file, but is any
valid BSON object for which work is to be performed.

A running batch job will be interrupted if a new job with a higher priority is queued for
processing.  This allows low priority jobs to use all available resources until a higher
priority job arrives, and then to resume processing once the higher priority job is complete.

~~~ruby
class ReverseJob < RocketJob::Job
  include RocketJob::Batch

  # Keep the job around after it has finished
  self.destroy_on_complete = false

  # Number of lines/records for each slice
  input_category slice_size: 100

  # Collect any output from the job
  output_category

  def perform(line)
    # Work on a single record at a time across many workers
  end
end
~~~

Queue the job for processing:

~~~ruby
# Words would come from a database query, file, etc.
words = %w(these are some words that are to be processed at the same time on many workers)

job = ReverseJob.new

# Load words as individual records for processing into the job
job.upload do |records|
  words.each do |word|
    records << word
  end
end

# Queue the job for processing
job.save!
~~~

### Batch Output

Display the output from the above batch:

~~~ruby
# Display the results that were returned
job.output.each do |slice|
  slice.each do |record|
    # Display each record returned from job
    puts record
  end
end
~~~

### Output Ordering

The order of the slices and records is exactly the same as the order in which the records were uploaded into the job.
This makes it easy to correlate an input record with its corresponding output record.

There are cases however where the exact input and output record ordering can be changed:
- When an input file has a header row, for example CSV, but the output file does not require one, for example JSON or XML.
    - In this case the output file is just missing the header row, so every record / line will be off by 1.
- By specifying `nils: false` on the output category it skips any records for which `nil` was returned by the `perform` method.

### Job Completion

The output from a job can be queried at any time, but will be incomplete until the job has completed processing.

To programatically wait for a job to complete processing:

~~~ruby
loop do
  sleep 1
  job.reload
  break unless job.running? || job.queued?
  puts "Job is still #{job.state}"
end
~~~


### Large File Processing

Batch jobs can process very large files. Entire files are uploaded into a Job for processing
and automatically broken up into slices for workers to process.

Queue the job for processing:

~~~ruby
job = ReverseJob.new
# Upload a file into the job for processing
job.upload('myfile.txt')
job.save!
~~~

Once the job has completed, download the output records into a file:

~~~ruby
# Download the output and compress the output into a GZip file
job.download('reversed.txt.gz')
~~~

Rocket Job has built-in support for reading and writing

* `Zip` files
* `GZip` files
* files encrypted with [Symmetric Encryption][3]
* delimited files
    * Windows CR/LF text files
    * Linux text files
    * Auto-detects Windows or Linux line endings
    * Any custom delimiter
* files with fixed length records

Note:

* In order to read and write `Zip` on CRuby, add the gem `rubyzip` to your `Gemfile`.
* Not required with JRuby since it will use the native `Zip` support built into Java

### Uploading data

Rocket Job uploads the data for the job into a unique Mongo Collection for every batch job. During processing
the slices are removed from this collection as soon as they are processed.

Failed slices remain in the collection and are marked as failed so that they can be investigated or retried.

Benefits of uploading data into the job:
- Does not require access across all of the workers to the original file or data during processing.
- The file can be decompressed and / or unencrypted before it is broken up into slices.
- Does not require a separate data store to hold the jobs input data.
- Rocket Job transparently takes care of the storage and retrieval of the uploaded data.
- Since a slice now has state, it can be failed, and holds the exception that occurred when trying to process that slice.
- Each slice that is being processed contains the name of the worker currently processing it.

Data can be uploaded into a batch job from many sources:
- File.
- Active Record query.
- Mongoid query.
- A block of code.

#### Uploading Files

Upload every line in a file as records into the job for processing.

Returns the number of lines uploaded into the job as an `Integer`.

Parameters

- `file_name_or_io` `[String | IO]`
    - Full path and file name to stream into the job.
    - Or, an IOStream that responds to: `read`

- `streams` `[Symbol|Array]`
    - Streams to convert the data whilst it is being read.
    - When nil, the file_name extensions will be inspected to determine what
      streams should be applied.
    - Default: nil

- `delimiter` `[String]`
    - Line / Record delimiter to use to break the stream up into records
        - Any string to break the stream up by
        - The records when saved will not include this delimiter
    - Default: nil
        - Automatically detect line endings and break up by line
        - Searches for the first "\r\n" or "\n" and then uses that as the
          delimiter for all subsequent records

- `buffer_size` `[Integer]`
    - Size of the blocks when reading from the input file / stream.
    - Default: 65536 ( 64K )

- `encoding` `[String|Encoding]`
    - Encode returned data with this encoding.
        - 'US-ASCII':   Original 7 bit ASCII Format
        - 'ASCII-8BIT': 8-bit ASCII Format
        - 'UTF-8':      UTF-8 Format
        - Etc.
    - Default: 'UTF-8'

- `encode_replace` `[String]`
    - The character to replace with when a character cannot be converted to the target encoding.
    - nil: Don't replace any invalid characters. Encoding::UndefinedConversionError is raised.
    - Default: nil

- `encode_cleaner` `[nil|symbol|Proc]`
    - Cleanse data read from the input stream.
    - `nil`: No cleansing
    - `:printable`: Cleanse all non-printable characters except \r and \n
    - Proc / lambda:    Proc to call after every read to cleanse the data
    - Default: :printable

- `stream_mode` `[:line | :array | :hash]`
    - `:line`
        - Uploads the file a line (String) at a time for processing by workers.
    - `:array`
        - Parses each line from the file as an Array and uploads each array for processing by workers.
    - `:hash`
        - Parses each line from the file into a Hash and uploads each hash for processing by workers.
    - See `IOStream#each`.
    - Default: `:line`

Example, load plain text records from a file

~~~ruby
job.upload('hello.csv')
~~~

Example:

Load plain text records from a file, stripping all non-printable characters,
as well as any characters that cannot be converted to UTF-8
~~~ruby
job.upload('hello.csv', encode_cleaner: :printable, encode_replace: '')
~~~

Example: Zip
~~~ruby
job.upload('myfile.csv.zip')
~~~

Example: Encrypted Zip

~~~ruby
job.upload('myfile.csv.zip.enc')
~~~
Example: Explicitly set the streams

~~~ruby
job.upload('myfile.ze', streams: [:zip, :enc])
~~~

Example: Supply custom options
~~~ruby
job.upload('myfile.csv.enc', streams: :enc])
~~~

Example: Extract streams from filename but write to a temp file

~~~ruby
streams = IOStreams.streams_for_file_name('myfile.gz.enc')
t = Tempfile.new('my_project')
job.upload(t.to_path, streams: streams)
~~~

Notes:
- By default all data read from the file/stream is converted into UTF-8 before being persisted. This
  is recommended since Mongo only supports UTF-8 strings.
- When zip format, the Zip file/stream must contain only one file, the first file found will be
  loaded into the job
- If an io stream is supplied, it is read until it returns nil.
- Only call from one thread at a time per job instance.
- CSV parsing is slow, so it is left for the workers to do.

See: [IOStreams](https://github.com/rocketjob/iostreams) for more information on supported file types and conversions
that can be applied during calls to `upload` and `download`.

#### Active Record Queries

Upload results from an Active Record Query into a batch job.

Parameters
- `column_names`
    - When a block is not supplied, supply the names of the columns to be returned   
      and uploaded into the job.
    - These columns are automatically added to the select list to reduce overhead.
    - Default: `:id`

If a Block is supplied it is passed the model returned from the database and should
return the work item to be uploaded into the job.

Returns [Integer] the number of records uploaded

Example: Upload id's for all users
~~~ruby                                                 
arel = User.all                                                                  
job.upload_arel(arel)                                         
~~~

Example: Upload selected user id's
~~~ruby
arel = User.where(country_code: 'US')
job.upload_arel(arel)                                         
~~~

Example: Upload user_name and zip_code
~~~ruby                                                 
arel = User.where(country_code: 'US')                                            
job.upload_arel(arel, :user_name, :zip_code)                  
~~~

#### Mongoid Queries

Upload the result of a MongoDB query to the input collection for processing.
Useful when an entire MongoDB collection, or part thereof needs to be
processed by a job.

Returns [Integer] the number of records uploaded

If a Block is supplied it is passed the document returned from the
database and should return a record for processing.

If no Block is supplied then the record will be the :fields returned
from MongoDB.

Notes:
- This method uses the collection directly and not the Mongoid document to
  avoid the overhead of constructing a model with every document returned
  by the query.
- The Block must return types that can be serialized to BSON.
    - Valid Types: `Hash | Array | String | Integer | Float | Symbol | Regexp | Time`
    - Invalid: `Date`, etc.
    - With a `Hash`, the keys must be strings and not symbols.

Example: Upload document ids

~~~ruby
criteria = User.where(state: 'FL')
job.upload_mongo_query(criteria)
~~~

Example: Specify one or more columns other than just the document id to upload:

~~~ruby
criteria = User.where(state: 'FL')
job.upload_mongo_query(criteria, :zip_code)
~~~

#### Upload Block

When a block is supplied, it is given a record stream into which individual records can be written.

Upload by writing records one at a time to the upload stream.
~~~ruby
job.upload do |writer|
  10.times { |i| writer << i }
end
~~~

### Batch Job Throttling

Throttle the number of workers that can work on a batch job instance at any time.

Limiting can be used when too many concurrent workers are:

* Overwhelming a third party system by calling it too frequently.
* Impacting the online production systems by writing too much data too quickly to the master database.

Worker limiting also allows batch jobs to be processed concurrently instead of sequentially.

The `throttle_running_workers` throttle can be changed at any time, even while the job is running to
either increase or decrease the number of workers working on that job.

~~~ruby
class ReverseJob < RocketJob::Job
  include RocketJob::Batch

  # No more than 10 workers should work on this job at a time
  self.throttle_running_workers = 10

  def perform(line)
    line.reverse
  end
end
~~~

### Multiple Output Files

A single batch job can also create multiple output files by categorizing the result
of the perform method.

This can be used to output one file with results from the job and another for
outputting for example the lines that were too short.

~~~ruby
class MultiFileJob < RocketJob::Job
  include RocketJob::Batch

  self.destroy_on_complete = false

  output_category
  # Register additional `:invalid` output category for this job
  output_category(name: :invalid)

  def perform(line)
    if line.length < 10
      # The line is too short, send it to the invalid output collection
      Result.new(line, :invalid)
    else
      # Reverse the line ( default output goes to the :main output collection )
      line.reverse
    end
  end
end
~~~

When complete, download the results of the batch into 2 files:

~~~ruby
# Download the regular results
job.download('reversed.txt.gz')

# Download the invalid results to a separate file
job.download('invalid.txt.gz', category: :invalid)
~~~

### Error Handling

Since a Batch job breaks a single job into slices, individual records within
slices can fail while others are still being processed.

~~~ruby
# Display the exceptions for failed slices:
job = RocketJob::Job.find('55bbce6b498e76424fa103e8')
job.input.each_failed_record do |record, slice|
  p slice.exception
end
~~~

Once all slices have been processed and there are only failed slices left, then the job as a whole
is failed.

### Reading Tabular Files

Very often received data is in a format very similar to that of a spreadsheet
with rows and columns, such as CSV, or Excel files.
Usually the first row is the header that describes what each column contains.
The remaining rows are the actual data for processing.

To direct Rocket Job Batch to read the input as csv, add the `format` option to the `input_category`.
Now each CSV line will be parsed just before the `perform` method is called, and
a Hash will be passed in as the first argument to `perform`, instead of the csv line.

This `Hash` consists of the header field names as keys and the values that were received for the specific row
in the file.

~~~ruby
class TabularJob < RocketJob::Job
  input_category format: :csv
  
  def perform(record)
  #  record is a Hash, for example: 
  #  {
  #     "first_field" => 100,
  #     "second"      => 200,
  #     "third"       => 300
  #   }
  end
end
~~~

Upload a file into the job for processing
~~~ruby
job = TabularJob.new
job.upload('my_really_big_csv_file.csv')
job.save!
~~~

Notes:
- In the above example, the file is uploaded into the job in its entirety before the job is saved.
- It is possible to save the job prior to uploading the file, but if the file upload fails workers will have already
  processed much of the data that was uploaded.
- The file is uploaded using a stream so that the entire file is not loaded into memory. This allows extremely
  large files to be uploaded with minimal memory overhead.

This job can be changed so that it handles any supported tabular informat. For example: csv, psv, json, xlsx.

#### Auto Detect file type

Set the `format` to `:auto` to use the file name during the upload step to auto-detect the file type:

~~~ruby
class TabularJob < RocketJob::Job
  include RocketJob::Batch
  
  input_category format: :auto
  
  def perform(record)
  #  record is a Hash, for example: 
  #  {
  #     "first_field" => 100,
  #     "second"      => 200,
  #     "third"       => 300
  #   }
  end
end
~~~

Upload a csv file into the job for processing
~~~ruby
job = TabularJob.new
job.upload("my_really_big_csv_file.csv")
job.save!
~~~

Upload a xlsx spreadsheet with the same column headers into the same job for processing,
without changing the job in any way:
~~~ruby
job = TabularJob.new
job.upload("really_big.xlsx")
job.save!
~~~

And so on, for example reading a json file:
~~~ruby
job = TabularJob.new
job.upload("really_big.json")
job.save!
~~~


### Writing Tabular Files

Jobs can also output tabular data such as CSV files. Instead of making the job deal with CSV
transformations directly, it can set the `format` on the `output_category` to `:csv`:

~~~ruby
class ExportUsersJob < RocketJob::Job
  include RocketJob::Batch
  
  # Columns to include in the output file
  output_category format: :csv, columns: ["login", "last_login"]
  
  def perform(id)
    u = User.find(id)
    # Return a Hash that tabular will render to CSV
    {
      "login"      => u.login,
      "last_login" => u.updated_at
    }
  end
end
~~~

Upload a file into the job for processing
~~~ruby
job = ExportUsersJob.new
# Upload the list of locked user logins to export.
arel = User.where(locked: true)
job.upload(arel)
job.save!
~~~

Once the job has completed, export the output:
~~~ruby
job.download("output.csv")
~~~

Sample contents of `output.csv`:
~~~csv
login,last_login
jbloggs,2019-02-11 05:43:20
kadams,2019-01-12 01:20:20
~~~

#### Filtering Output

Rocket Job will only export the list of columns specified, so for example the same job can output different
columns between runs. For Example, one customer gets more columns than other, and one job will handle both cases.

In the example below many attributes are being exported, yet only a subset is exported by default:

~~~ruby
class ExportUsersJob < RocketJob::Job
  include RocketJob::Batch
  
  # Columns to include in the output file
  output_category format: :csv, columns: ["login", "last_login"]
  
  def perform(login)
    u = User.find_by(login: login)
    # Return a Hash of all available attributes from which it will extract
    # the "login", "last_login" columns.
    u.attributes 
  end
end
~~~

Run the job:
~~~ruby
job = ExportUsersJob.create!
~~~

Once the job has completed, export the output:
~~~ruby
job.download("output.csv")
~~~

Sample contents of `output.csv`:
~~~csv
login,last_login
jbloggs,2019-02-11 05:43:20
kadams,2019-01-12 01:20:20
~~~

For another customer the list of columns can be increased by overriding the output columns.
For example, make the job output a CSV file with the "login", "last_login", "name", and "state" columns:

~~~ruby
job = ExportUsersJob.new
job.output_category.columns = ["login", "last_login", "name", "state"]
job.save!
~~~

Once the job has completed, export the output:
~~~ruby
job.download("output.csv")
~~~

Sample contents of `output.csv`:
~~~csv
login,last_login,name,state
jbloggs,2019-02-11 05:43:20,Joe Bloggs,FL
kadams,2019-01-12 01:20:20,Kevin Adams,TX
~~~

---
### Single Output File

Example: Process a very large csv file and return a single output csv file:

~~~ruby
class MultiFileJob < RocketJob::Job
  include RocketJob::Batch

  # Prevent this job from being destroyed on completion.
  self.destroy_on_complete = false

  # Specify that the main input category should parse the uploaded CSV file
  # and pass each line one at a time into the `perform` method. 
  input_category format: :csv
  
  # Register an output category to output a CSV file.
  output_category format: :csv

  # When the job completes automatically download the output files.
  after_batch :download_file
  
  # Since the input category has format: :csv, the `perform` method will receive a hash:
  # {
  #   "first_name" => "Jack",
  #   "last_name" => "Jones",
  #   "age" => "21",
  #   "zip_code" => "12345"
  # }
  def perform(row)
    # Since the output_category format is `:csv`, Rocket Job will convert this hash into a line in the csv file.
    {
      name: "#{row['first_name'].downcase} #{row['last_name'].downcase}",
      age:  row["age"]
    }
  end

  # Download the output from this job into a CSV file
  def download_file
    download("names.csv")
  end
end
~~~


### Multiple Output Files

When multiple output files need to be created, add a second output category to hold its contents.

For example, the upload file is a csv file as follows, by running this code in a Rails console:

~~~ruby
# Create a sample CSV file to test with:
str = <<STRING
First Name, Last name, age, zip code
Jack,Jones,21,12345
Mary,Jane,32,55512
STRING
~~~ruby

Now display the file contents as hashes: 
~~~ruby
io = StringIO.new(str)
IOStreams.stream(io).each(:hash) {|h| p h}
~~~

The output from the above code:
~~~ruby
{"first_name"=>"Jack", "last_name"=>"Jones", "age"=>"21", "zip_code"=>"12345"}
{"first_name"=>"Mary", "last_name"=>"Jane", "age"=>"32", "zip_code"=>"55512"}
~~~

Now lets build a job to process the file above and create 2 output files:
~~~ruby
class MultiFileJob < RocketJob::Job
  include RocketJob::Batch

  # Prevent this job from being destroyed on completion.
  self.destroy_on_complete = false

  # Instruct the main input category to parse each line of the csv file,
  # pass them in one at a time into the `perform` method. 
  input_category format: :csv
  
  # Register a main output category to output a CSV file.
  output_category name: :main, format: :csv

  # Register a `zip_codes` output category to output a separate CSV file.
  output_category name: :zip_codes, format: :csv
  
  # When the job completes automatically download the output files.
  after_batch :download_files
  
  # Since the input category has format: :csv, the `perform` method will receive a hash:
  # {
  #   "first_name" => "Jack",
  #   "last_name" => "Jones",
  #   "age" => "21",
  #   "zip_code" => "12345"
  # }
  def perform(row)
    # Collect multiple outputs into this collection
    outputs = RocketJob::Batch::Results.new
    
    # Lets output the names into the main file:
    main_result = {
      name: "#{row['first_name'].downcase} #{row['last_name'].downcase}",
      age:  row["age"]
    }
    # Add the result to the main output category:
    outputs << main_result

    # And the zip codes into the zip_codes file:
    zip_codes_result = {
      zip: row["zip_code"]
    }

    # Add the zip codes result to the zip_code output category:
    outputs << RocketJob::Batch::Result.new(:zip_codes, zip_codes_result)
    
    # Return the collected outputs
    outputs
  end
  
  def download_files
    # Download the main output file
    download("names.csv")
    
    # Download the zip_codes output file
    download("zip_codes.csv", category: :zip_codes)
  end
end
~~~

### Compression

Compression reduces network utilization and disk storage requirements.
Highly recommended when processing large files, or large amounts of data.

By setting the input and output categories `serializer` to `:compress` it ensures that all data uploaded into
this job is compressed.

By default with Rocket Job v6 the default serializer is now `:compress`. Set it to `:none` to disable compression.

~~~ruby
class ReverseJob < RocketJob::Job
  include RocketJob::Batch

  # Compress input and output data
  input_category serializer: :compress
  output_category serializer: :compress

  def perform(line)
    line.reverse
  end
end
~~~

### Encryption

By setting the input and output categories `serializer` to `:encrypt` it ensures that all data uploaded into
this job is encrypted.
Encryption helps ensure sensitive data meets compliance requirements both at rest and in-flight.

When encryption is enabled, the data is automatically compressed before encryption to reduce the amount of data
that is encrypted and unencrypted.

~~~ruby
class ReverseJob < RocketJob::Job
  include RocketJob::Batch

  # Encrypt input and output data
  input_category serializer: :encrypt
  output_category serializer: :encrypt

  def perform(line)
    line.reverse
  end
end
~~~

#### PGP Encryption

When exchanging files with other systems, using an open standard like PGP is ideal.

Below is an example on how to create a PGP encrypted output file: 

~~~ruby
class MultiFileJob < RocketJob::Job
  include RocketJob::Batch

  # Prevent this job from being destroyed on completion.
  self.destroy_on_complete = false

  # Specify that the main input category should parse the uploaded CSV file
  # and pass each line one at a time into the `perform` method. 
  input_category format: :csv
  
  # Register an output category to output a CSV file.
  output_category format: :csv

  # Define a field to hold the `pgp_public_key` of the recipient.
  field :pgp_public_key, type: String
  
  validates_presence_of :pgp_public_key

  # When the job completes automatically download the output files.
  after_batch :download_file

  # Since the input category has format: :csv, the `perform` method will receive a hash:
  # {
  #   "first_name" => "Jack",
  #   "last_name" => "Jones",
  #   "age" => "21",
  #   "zip_code" => "12345"
  # }
  def perform(row)
    # Since the output_category format is `:csv`, Rocket Job will convert this hash into a line in the csv file.
    {
      name: "#{row['first_name'].downcase} #{row['last_name'].downcase}",
      age:  row["age"]
    }
  end

  # Download the output from this job into a CSV file encrypted with PGP
  def download_file
    path = IOStreams.path("names.csv")
    
    # Add the pgp public key to encrypt the file with:
    path.option(:pgp, import_and_trust_key: pgp_public_key)
    
    download(path)
  end
end
~~~

