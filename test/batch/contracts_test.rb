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
