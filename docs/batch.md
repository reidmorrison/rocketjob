---
layout: default
---

## Batch Processing

Regular jobs run on a single worker. In order to scale up and use all available workers
it is necessary to break up the input data into "slices" so that different parts of the job
can be processed in parallel.

Jobs that include `RocketJob::Batch` break their work up into slices so that many workers can work
on the individual slices at the same time. Slices take a large and unwieldy batch job and break it up
into "bite-size" pieces that can be processed a slice at a time by the workers.

Because Batch jobs consists of lots of smaller slices they can be paused, resumed, or even aborted as a whole.
If there are any failed slices when the job finishes, they can all be retried by retrying the job itself.

For example, using the default `slice_size` of 100, if the file contains 1,000,000
lines then this job will contain only 10,000 slices.

A running batch Job will be interrupted if a new job with a higher priority is queued for
processing.  This allows low priority jobs to use all available resources until a higher
priority job arrives, and then to resume processing once the higher priority job is complete.

~~~ruby
class ReverseJob < RocketJob::Job
  include RocketJob::Batch

  # Number of lines/records for each slice
  self.slice_size          = 100

  # Keep the job around after it has finished
  self.destroy_on_complete = false

  # Collect any output from the job
  self.collect_output      = true

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
    # Display each result returned from job
    puts record
  end
end
~~~

The order of the output gathered above is exactly the same as the order in which the records
were uploaded into the job. This makes it easy to correlate an input record with its corresponding output.

### Batch Large File Processing

Rocket Job batch jobs supports very large files. It can easily upload
entire files into the Job for processing and automatically slices up the records in
the file into slices for processing.

Queue the job for processing:

~~~ruby
job = ReverseJob.new
# Upload a file into the job for processing
job.upload('myfile.txt')
job.save!
~~~

When complete, download the results of the batch into a file:

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

* In order to read and write `Zip` on Ruby MRI, add the gem `rubyzip` to your `Gemfile`.
* Not required with JRuby since it will use the native `Zip` support built into Java

### Worker Limiting / Throttling

Throttle the number of workers that can work on a batch job instance at any time.

Limiting can be used when too many concurrent workers are:

* Overwhelming a third party system by calling it too frequently.
* Impacting the online production systems by writing too much data too quickly to the master database.

Worker limiting also allows batch jobs to be processed concurrently instead of sequentially.

The `throttle_running_slices` throttle can be changed at any time, even while the job is running to
either increase or decrease the number of workers working on that job.

~~~ruby
class ReverseJob < RocketJob::Job
  include RocketJob::Batch

  # No more than 10 workers should work on this job at a time
  self.throttle_running_slices = 10

  def perform(line)
    line.reverse
  end
end
~~~

### Directory Monitor

Directory Monitor can be used to monitor directories for new files and then to
load the entire file into the job for processing. The file is then either archived,
or deleted based on the configuration for that path.

### Multiple Output Files

A single batch job can also create multiple output files by categorizing the result
of the perform method.

This can be used to output one file with results from the job and another for
outputting for example the lines that were too short.

~~~ruby
class MultiFileJob < RocketJob::Job
  include RocketJob::Batch

  self.collect_output      = true
  self.destroy_on_complete = false
  # Register additional `:invalid` output category for this job
  self.output_categories   = [ :main, :invalid ]

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

## Error Handling

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

## Batch Processing How To

Very often data that is being received is in a format very similar to that of a spreadsheet
with rows and columns. Usually the first row is the header that describes what each column contains.
The remaining rows are the actual data for processing. Tabular processing is built into Rocket Job Pro.
CSV format is set as default. See Tabular page for details.

~~~ruby
class MultiFileJob < RocketJob::Job
  include RocketJob::Batch
  include RocketJob::Batch::Tabular
  
  def perform(row)
  #  row is a hash: 
  #  {
  #     "first_field" => 100,
  #     "second"      => 200,
  #     "third"       => 300
  #   }
  end
end
~~~

When multiple output files are created with Tabular, the first output should be passed in as a hash,
second - as an array.

~~~ruby
class MultiFileJob < RocketJob::Job
  include RocketJob::Batch
  include RocketJob::Batch::Tabular

  self.collect_output      = true
  self.destroy_on_complete = false
  # Register additional `:invalid` output category for this job
  self.output_categories   = [ :main, :invalid ]
  
  # row = {
  #        'first_field' => 100,
  #             'second' => 200,
  #              'third' => 300
  #       }
  def perform(row)
    
    if row['first_field'] != 0
     # Pass hash to fill the first CSV file
     result = {
       first_result:  row['first_field'] * 2,
       second_result: row['second'] * 2,
       third_result:  row['third'] * 2
     }
     # RocketJob::Batch::Result handles writing result to the main output file
     RocketJob::Batch::Result.new(:main, result)
    else
     # error condition: return file in input format, add extra column with error message.
     # Pass array instead of hash to fill in the second CSV file correctly
     # Order of the array must be the order of the column headings for accuracy
      
     result = [
                row["first_field"],
                row["second"],
                row["third"],
                'first field can not be 0'
     ]
     # RocketJob::Batch::Result handles writing result to the invalid output file
     RocketJob::Batch::Result.new(:invalid, result) 
    end
  end
  
  def invalid_file_header
    @invalid_file_header ||= begin
      raise('Cannot create output invalid header until in the input header is known') unless tabular_input_header

      tabular_input_header + ['error']
    end
  end 
end
~~~


When complete, we download results into separate batch files. Often there is the need to encrypt sensitive data.
When output files are encrypted using PGP encryption, there is often no way to decrypt these files.
In this case it is a good practice to create audit files using build-in Symmetric Encryption.


~~~ruby
class MultiFileJob < RocketJob::Job
  include RocketJob::Batch
  include RocketJob::Batch::Tabular

  self.collect_output      = true
  self.destroy_on_complete = false
  self.output_categories   = [ :main, :invalid ]
  
  field :output_path, type: String
  field :pgp_public_key, type: String
    
  field :main_output_file_name, type: String
  field :invalid_output_file_name, type: String
  
  field :main_audit_file_name, type: String
  field :invalid_audit_file_name, type: String
  
  before_batch :set_output_file_names
  before_complete :download_file, :download_audit_file
  
  def set_output_file_names
    path        = File.join('downloads', self.class.collective_name)
    output_path = output_path.present? ? output_path : path
    FileUtils.mkdir_p(path) unless File.exist?(path)
    
    self.main_output_file_name = File.join(output_path, "out_main_#{id.to_s}.csv.pgp")
    self.invalid_output_file_name = File.join(output_path, "out_invalid_#{id.to_s}.csv.pgp")
    
    # keep copies of the file for diagnostics.
    self.main_audit_file_name = File.join(path, "out_main_audit_#{id.to_s}.csv.enc")
    self.invalid_audit_file_name = File.join(path, "out_invalid_audit_#{id.to_s}.csv.enc")
  end
  
  def download_file
    IOStreams::Pgp.import(key: pgp_public_key)
    email = IOStreams::Pgp.key_info(key: pgp_public_key).first.fetch(:email)
    IOStreams::Pgp.set_trust(email: email)
    download(main_output_file_name, category: :main, streams: [pgp: {compression: :zlib, recipient: email}])
    download(invalid_output_file_name, category: :invalid, streams: [pgp: {compression: :zlib, recipient: email}])
    rescue Exception => e
      File.delete(main_output_file_name) if main_output_file_name && File.exist?(main_output_file_name)
      File.delete(invalid_output_file_name) if invalid_output_file_name && File.exist?(invalid_output_file_name)
      raise e
  end
  
  def download_audit_file
    download(main_audit_file_name,  category: :main, streams: [enc: {compress: true}])
    download(invalid_audit_file_name, category: :invalid, streams: [enc: {compress: true}])
    rescue Exception => e
      File.delete(main_audit_file_name) if main_audit_file_name && File.exist?(main_audit_file_name)
      File.delete(invalid_audit_file_name) if invalid_audit_file_name && File.exist?(invalid_audit_file_name)
      raise e
  end
end  
~~~

Below is an example of testing functionality above using Minitest:
~~~ruby
class MultiFileJobTest < ActiveSupport::TestCase

  let :job do
    job = MultiFileJob.new(
      pgp_public_key:    IOStreams::Pgp.export(email: 'receiver@example.org'),
      output_path:       'output_path'
    )
  end
  
  let :valid_row do
    "first_field,second,third\n100,200,300"
  end
  
  describe 'perform' do
    it 'creates main output file' do
      job.upload(StringIO.new(valid_row), file_name: 'a.csv')
      job.perform_now
      result = IOStreams.reader(
        job.main_output_file_name, 
        iostreams: {pgp: {passphrase: 'receiver_passphrase'}},
        &:read
      )
      header, row, remainder = CSV.parse(result)
      
      assert_equal header.size, row.size
      assert_nil remainder
     
      assert_equal 100, row[0]
      assert_equal 200, row[1]
      assert_equal 300, row[2]
    end
  end
end
~~~

[0]: http://rocketjob.io
[1]: mission_control.html
[3]: http://rocketjob.github.io/symmetric-encryption
