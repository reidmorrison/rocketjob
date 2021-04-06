---
layout: default
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
