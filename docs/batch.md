---
layout: default
---

### Multiple Output Files

When multiple output files are created using the tabular plugin, the first output should be passed in as a hash,
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

Upon completion download the results into separate files. Often there is the need to encrypt sensitive data.
When output files are encrypted using PGP encryption, there is often no way to decrypt these files.
In this case it is a good practice to create audit files using built-in Symmetric Encryption.

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
      result = IOStreams.path(
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
