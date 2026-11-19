require_relative "../test_helper"

module Batch
  class ContractsTest < Minitest::Test
    class OrderContract < IOStreams::Contract
      fields_match "partial"

      field :id,     :integer, required: true
      field :amount, :number,  decimals: 2
    end

    class ContractJob < RocketJob::Job
      include RocketJob::Batch

      self.destroy_on_complete = false

      input_contract do
        fields_match "partial"

        field :id,     :integer, required: true
        field :amount, :number,  decimals: 2
      end

      output_category

      # Keeps each record that #perform receives, with its record and line number, to check them.
      def perform(order)
        {"class" => order.class.name, "order" => order.to_h, "record" => rocket_job_record_number, "line" => rocket_job_line_number}
      end
    end

    class RangeJob < RocketJob::Job
      include RocketJob::Batch

      self.destroy_on_complete = false

      input_contract do
        field :start, :integer
        field :stop,  :integer
      end

      output_category

      def perform(range)
        range.stop - range.start
      end
    end

    class ExactJob < RocketJob::Job
      include RocketJob::Batch

      self.destroy_on_complete = false

      input_contract do
        field :id,     :integer
        field :amount, :number
      end

      output_category

      def perform(order)
        order.to_h
      end
    end

    class PlainJob < RocketJob::Job
      include RocketJob::Batch

      def perform(record)
        record
      end
    end

    describe RocketJob::Batch::Contracts do
      describe ".input_contract" do
        it "builds the contract of a block as the class InputContract within the job class" do
          assert_equal ContractJob::InputContract, ContractJob.input_contract
          assert_operator ContractJob.input_contract, :<, IOStreams::Contract
          assert_equal %w[id amount], ContractJob.input_contract.fields.map(&:name)
        end

        it "takes a contract class" do
          job_class = Class.new(PlainJob) { input_contract OrderContract }

          assert_equal OrderContract, job_class.input_contract
        end

        it "is nil without a contract" do
          assert_nil PlainJob.input_contract
        end

        it "raises for both a contract class and a block" do
          error = assert_raises(ArgumentError) do
            Class.new(PlainJob) { input_contract(OrderContract) { field :id, :integer } }
          end

          assert_includes error.message, "not both"
        end

        it "raises for a class that is not a contract" do
          error = assert_raises(ArgumentError) { Class.new(PlainJob) { input_contract Hash } }

          assert_includes error.message, "subclass of IOStreams::Contract"
        end

        it "keeps the contract of the parent class in a subclass, which can replace it for itself only" do
          subclass = Class.new(ContractJob)

          assert_equal ContractJob::InputContract, subclass.input_contract

          subclass.input_contract(OrderContract)

          assert_equal OrderContract, subclass.input_contract
          assert_equal ContractJob::InputContract, ContractJob.input_contract
        end
      end

      describe "the main input category" do
        it "reads the format of each file from its name, when it has none" do
          assert_equal :auto, ContractJob.new.input_category.format
        end

        it "keeps the format that the job class sets" do
          job_class = Class.new(ContractJob) { input_category format: :psv }

          assert_equal :psv, job_class.new.input_category.format
        end

        it "reads the format from the file name when the job class declares the category without a format" do
          job_class = Class.new(ContractJob) { input_category slice_size: 10 }

          assert_equal :auto, job_class.new.input_category.format
        end

        it "keeps a format of nil that the job class declares" do
          job_class = Class.new(ContractJob) { input_category format: nil }

          assert_nil job_class.new.input_category.format
        end

        it "has no format without a contract, as before" do
          assert_nil PlainJob.new.input_category.format
        end
      end

      describe "the schema of the main input category" do
        let(:missing_id) { {"fields" => [{"name" => "amount", "type" => "number"}]} }
        let(:with_id) do
          {"fields" => [{"name" => "id", "type" => "integer", "constraints" => {"required" => true}}, {"name" => "amount", "type" => "number"}]}
        end

        it "is checked against the contract when the job is saved" do
          job = ContractJob.new
          job.input_category.schema = missing_id

          refute_predicate job, :valid?
          assert_includes job.errors.messages[:input_categories].join, "id"
        end

        it "is valid when every file that it reads meets the contract" do
          job = ContractJob.new
          job.input_category.schema = with_id

          assert_predicate job, :valid?, -> { job.errors.full_messages.inspect }
        end

        it "is not checked again when a job is saved without a change to its categories, such as by a worker" do
          job = ContractJob.new
          job.input_category.schema = missing_id
          job.save!(validate: false)
          job = ContractJob.find(job.id)
          job.description = "running"

          assert_predicate job, :valid?, -> { job.errors.full_messages.inspect }
        ensure
          job&.destroy
        end

        it "is checked in the properties of a Dirmon entry, without building the job" do
          properties = {"input_categories" => [{"name" => "main", "schema" => missing_id}]}

          assert_equal 1, ContractJob.property_errors(properties).size
          assert ContractJob.property_errors(properties).first.start_with?("Input category main: ")
          assert_empty ContractJob.property_errors({"input_categories" => [{"name" => "main", "schema" => with_id}]})
        end
      end

      describe ".input_contract_errors" do
        def with_file(extension, data)
          IOStreams.temp_file("contracts_test", extension) do |path|
            ::File.write(path.to_s, data)
            yield(path.to_s)
          end
        end

        it "is empty for a file that meets the contract" do
          with_file(".csv", "ID,Amount\n1,2\n") { |path| assert_empty ContractJob.input_contract_errors(path) }
        end

        it "names each column that the contract requires and the file does not have" do
          errors = with_file(".csv", "amount\n1\n") { |path| ContractJob.input_contract_errors(path) }

          assert_equal [IOStreams::Errors::InvalidHeader], errors.map(&:class)
          assert_includes errors.first.message, "id"
        end

        it "is empty without a contract" do
          with_file(".csv", "amount\n1\n") { |path| assert_empty PlainJob.input_contract_errors(path) }
        end

        it "merges each main input category of the properties, in order, as the job is built from them" do
          properties = {"input_categories" => [{"format" => "csv"}, {"name" => "main", "format" => "psv"}]}

          with_file(".txt", "id|amount\n1|2\n") { |path| assert_empty ContractJob.input_contract_errors(path, properties) }
        end

        it "is empty for a job class without a main input category" do
          job_class = Class.new(ContractJob) { input_category name: :orders }
          job_class.defined_input_categories = job_class.defined_input_categories.reject { |category| category.name == :main }

          with_file(".csv", "amount\n1\n") { |path| assert_empty job_class.input_contract_errors(path) }
        end

        it "ignores an entry of the properties that is not a Hash, which property_errors reports" do
          with_file(".csv", "id\n1\n") { |path| assert_empty ContractJob.input_contract_errors(path, {"input_categories" => ["main"]}) }
        end

        it "reads the file as the properties of the job say, without building it" do
          properties = {"input_categories" => [{"name" => "main", "format" => "psv"}]}

          with_file(".txt", "id|amount\n1|2\n") do |path|
            assert_empty ContractJob.input_contract_errors(path, properties)
            refute_empty ContractJob.input_contract_errors(path, {"input_categories" => [{"name" => "main", "format" => "csv"}]})
          end
        end

        it "reads the format of a file from the name that it was uploaded with" do
          with_file(".bin", %({"id":1}\n)) do |path|
            assert_empty ContractJob.input_contract_errors(path, original_file_name: "orders.json")
          end
        end
      end

      describe "an UploadFileJob" do
        it "fails before it uploads any slice, naming each column that the contract requires, for a file without them" do
          IOStreams.temp_file("contracts_test", ".csv") do |path|
            ::File.write(path.to_s, "other\n1\n")
            upload = RocketJob::Jobs::UploadFileJob.new(job_class_name: ContractJob.name, upload_file_name: path.to_s)
            count  = ContractJob.count

            error = assert_raises(IOStreams::Errors::InvalidHeader) { upload.perform }

            assert_includes error.message, 'missing the required field "id"'
            assert_equal count, ContractJob.count
          end
        end
      end

      describe "upload" do
        let(:job) { ContractJob.new }

        after do
          job.cleanup!
        end

        def upload(extension, data, job: self.job, **)
          IOStreams.temp_file("contracts_test", extension) do |path|
            ::File.write(path.to_s, data)
            job.upload(path.to_s, **)
          end
        end

        it "raises for a file without a column that the contract requires, before it uploads any slice" do
          error = assert_raises(IOStreams::Errors::InvalidHeader) { upload(".csv", "amount\n1\n") }

          assert_includes error.message, "id"
          assert_equal 0, job.input.count
          assert_equal :auto, job.input_category.format
        end

        it "keeps the lines and header row of the file in each slice" do
          upload(".csv", "ID,Amount,Extra\n1,2.5,x\n")

          assert_equal %w[ID Amount Extra], job.input.first.records.header
          assert_equal ["1,2.5,x"], job.input.first.to_a
        end

        it "leaves the values to the workers, unless it validates the rows" do
          assert_equal 1, upload(".csv", "id\nx\n")

          job.input.delete_all
          assert_raises(IOStreams::Errors::InvalidValue) { upload(".csv", "id\nx\n", validate_rows: true) }
        end

        it "raises for lines written by a block without a column that the contract requires" do
          assert_raises(IOStreams::Errors::InvalidHeader) do
            job.upload do |lines|
              lines << "amount"
              lines << "1"
            end
          end
          assert_equal 0, job.input.count
        end

        it "raises for a file in a category without a format, whose columns a contract cannot read" do
          job_class = Class.new(ContractJob) { input_category format: nil }
          job       = job_class.new

          error = assert_raises(ArgumentError) { upload(".csv", "id\n1\n", job: job) }

          assert_includes error.message, "has no format"
          assert_equal 0, job.input.count
        ensure
          job&.cleanup!
        end

        it "uploads the rows of a query as they are, which the workers read through the contract" do
          RocketJob::Job.create!(description: "one")
          job_class = Class.new(ContractJob) do
            input_contract { field :description, :string }
            input_category format: :csv

            def perform(record)
              record.to_h
            end
          end
          job = job_class.new
          job.upload(RocketJob::Job.where(description: "one"), columns: [:description])
          job.save!
          job.perform_now

          assert_equal [{"description" => "one"}], job.output.collect(&:to_a).flatten(1)
        ensure
          job&.cleanup!
          RocketJob::Job.delete_all
        end

        it "leaves a value of a query that does not fit the contract to the workers" do
          RocketJob::Job.create!(description: "abc")
          job_class = Class.new(ContractJob) do
            input_contract { field :description, :integer }
            input_category format: :csv
          end
          job = job_class.new

          assert_equal 1, job.upload(RocketJob::Job.where(description: "abc"), columns: [:description])
          job.save!
          assert_raises(IOStreams::Errors::InvalidValue) { job.perform_now }
        ensure
          job&.cleanup!
          RocketJob::Job.delete_all
        end
      end

      describe "#perform" do
        let(:job) { ContractJob.new }

        after do
          job.cleanup!
        end

        def upload(extension, data, job: self.job)
          IOStreams.temp_file("contracts_test", extension) do |path|
            ::File.write(path.to_s, data)
            job.upload(path.to_s)
          end
        end

        def output_records(job = self.job)
          job.save!
          job.perform_now
          job.output.collect(&:to_a).flatten(1)
        end

        it "receives a record of the contract for each row of a CSV file, whatever its columns are named" do
          upload(".csv", "ID,Amount,Extra\n1,12.5,x\n2,3,y\n")

          assert_equal [
            {"class" => "Batch::ContractsTest::ContractJob::InputContract", "order" => {"id" => 1, "amount" => BigDecimal("12.5")}, "record" => 1, "line" => 2},
            {"class" => "Batch::ContractsTest::ContractJob::InputContract", "order" => {"id" => 2, "amount" => BigDecimal(3)}, "record" => 2, "line" => 3}
          ], output_records
        end

        it "receives the same records from a JSON file" do
          upload(".json", %({"id":1,"amount":"12.5"}\n{"id":2,"amount":3}\n))

          assert_equal([{"id" => 1, "amount" => BigDecimal("12.5")}, {"id" => 2, "amount" => BigDecimal(3)}],
                       output_records.map { |result| result["order"] })
        end

        it "skips a blank row, which still counts as a record" do
          upload(".csv", "id,amount\n1,1\n\n2,2\n")

          assert_equal([[1, 1, 2], [2, 3, 4]], output_records.map { |result| [result["order"]["id"], result["record"], result["line"]] })
        end

        it "points the failed slice at the record that failed after a blank row" do
          upload(".csv", "id,amount\n1,1\n\nx,2\n")
          job.save!

          assert_raises(IOStreams::Errors::InvalidValue) { job.perform_now }
          slice = job.input.failed.first

          assert_equal 3, slice.processing_at_record
          assert_equal "x,2", slice.failed_record
        end

        it "points a slice after its last row once every record is processed, also after a blank row" do
          upload(".csv", "id,amount\n1,1\n\n")
          job.save!
          job.define_singleton_method(:rocket_job_perform_slice) do |slice, &block|
            super(slice, &block)
            raise "after the records"
          end

          assert_raises(RuntimeError) { job.perform_now }
          slice = job.input.failed.first

          assert_equal 3, slice.processing_at_record
          assert_nil slice.failed_record
        end

        it "keeps the slice on its record when #perform raises a row error of another stream" do
          job_class = Class.new(ContractJob) do
            def perform(order)
              raise IOStreams::Errors::InvalidValue.new("other stream").at(record_number: 8) if order.id == 2

              super
            end
          end
          job = job_class.new
          job.upload_slice([{"id" => 1}, {"id" => 2}, {"id" => 3}])
          job.save!

          assert_raises(IOStreams::Errors::InvalidValue) { job.perform_now }
          assert_equal 2, job.input.failed.first.processing_at_record
        ensure
          job&.cleanup!
        end

        it "fails the slice for a value that is not of the type of its field, naming the field" do
          upload(".csv", "id,amount\n1,1\nx,2\n")
          job.save!

          assert_raises(IOStreams::Errors::InvalidValue) { job.perform_now }
          slice = job.input.failed.first

          assert_includes slice.exception.message, "id"
          assert_equal 2, slice.processing_at_record
        end

        it "receives each range as a record of a contract of its two ids, by position" do
          job = RangeJob.new
          job.input_category.slice_size = 10
          job.upload(1..25)

          assert_equal [9, 9, 4], output_records(job)
        ensure
          job&.cleanup!
        end

        it "raises for a range that the contract cannot read, before it uploads it" do
          error = assert_raises(ArgumentError) { job.upload(1..25) }

          assert_includes error.message, "cannot upload a Range"
          assert_equal 0, job.input.count
        end

        it "receives the Hashes of upload_slice as records of the contract" do
          job.upload_slice([{"id" => "1", "amount" => "1.5"}, {"id" => 2}])

          assert_equal([{"id" => 1, "amount" => BigDecimal("1.5")}, {"id" => 2, "amount" => nil}],
                       output_records.map { |result| result["order"] })
        end

        it "keeps a record of upload_slice whose values are all nil, which a required field then fails" do
          job.upload_slice([{"id" => 1}, {"id" => nil, "amount" => nil}])
          job.save!

          error = assert_raises(IOStreams::Errors::InvalidValue) { job.perform_now }

          assert_includes error.message, "id"
          assert_equal 2, job.input.failed.first.processing_at_record
        end

        it "receives the Arrays of upload_slice as records of a contract of their fields in order" do
          job = ExactJob.new
          job.upload_slice([["1", "1.5"], [2, 3]])

          assert_equal [{"id" => 1, "amount" => BigDecimal("1.5")}, {"id" => 2, "amount" => BigDecimal(3)}],
                       output_records(job)
        ensure
          job&.cleanup!
        end

        it "fails the slice of records that are neither Hashes nor Arrays" do
          job.upload_slice(%w[1,2])
          job.save!

          error = assert_raises(ArgumentError) { job.perform_now }

          assert_includes error.message, "Hashes or Arrays, such as those of upload_slice"
        end
      end
    end
  end
end
