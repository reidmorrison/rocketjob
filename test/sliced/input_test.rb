require_relative "../test_helper"

module Sliced
  class InputTest < Minitest::Test
    describe RocketJob::Sliced::Input do
      let(:collection_name) { "rocket_job.slices.test".to_sym }

      let :input do
        RocketJob::Sliced::Input.new(
          collection_name: collection_name,
          slice_size:      2
        )
      end

      let(:slice) { input.new(records: %w[hello world]) }
      let(:worker_name) { "ThisIsMe" }
      let(:lines) { %w[Line1 Line2 Line3] }
      let(:data) { lines.join("\n") + "\n" }

      before do
        input.delete_all
      end

      after do
        input.drop
      end

      describe "initialize" do
        it "create index" do
          input.upload { |io| io << "hello" }
          assert input.collection.indexes.any? { |i| i["name"] == "state_1__id_1" }, "must have state and _id index"
        end
      end

      describe "#upload with a block" do
        it "slice size 1" do
          input.slice_size = 1
          count = input.upload { |records| lines.each { |line| records << line } }
          assert_equal 3, count
          assert_equal 3, input.count
          assert_equal 1, input.first.first_record_number
          assert_equal 3, input.last.first_record_number
          result = input.collect(&:to_a).join("\n") + "\n"
          assert_equal data, result
        end

        it "slice size 2" do
          input.slice_size = 2
          count = input.upload { |records| lines.each { |line| records << line } }
          assert_equal 3, count
          assert_equal 2, input.count
          assert_equal 1, input.first.first_record_number
          assert_equal 3, input.last.first_record_number
          result = input.collect(&:to_a).join("\n") + "\n"
          assert_equal data, result
        end

        it "slice size 3" do
          input.slice_size = 3
          count = input.upload { |records| lines.each { |line| records << line } }
          assert_equal 3, count
          assert_equal 1, input.count
          assert_equal 1, input.first.first_record_number
          result = input.collect(&:to_a).join("\n") + "\n"
          assert_equal data, result
        end

        it "upload records according to slice_size" do
          count = input.upload do |records|
            (1..10).each { |i| records << i }
          end
          assert_equal 10, count
          assert_equal 5, input.count
          assert_equal [1, 2], input.first.to_a
          assert_equal [9, 10], input.last.to_a
        end

        it "upload no records" do
          count = input.upload do |_records|
            nil
          end
          assert_equal 0, count
          assert_equal 0, input.count
        end

        it "upload odd records according to slice_size" do
          count = input.upload do |records|
            (1..11).each { |i| records << i }
          end
          assert_equal 11, count
          assert_equal 6, input.count
          assert_equal [1, 2], input.first.to_a
          assert_equal [11], input.last.to_a
        end
      end

      describe "#upload_integer_range" do
        before do
          input.slice_size = 10
        end

        it "handle single value" do
          count = input.upload_integer_range(1, 1)
          assert_equal 1, count, input.first.inspect
          assert_equal [[[1, 1]]], input.collect(&:to_a)
        end

        it "handle single range" do
          count = input.upload_integer_range(1, 10)
          assert_equal 1, count, input.first.inspect
          assert_equal [[[1, 10]]], input.collect(&:to_a)
        end

        it "handle longer range" do
          count = input.upload_integer_range(1, 11)
          assert_equal 2, count, input.collect(&:to_a).inspect
          assert_equal [[[1, 10]], [[11, 11]]], input.collect(&:to_a)
        end

        it "handle even longer range" do
          count = input.upload_integer_range(0, 44)
          assert_equal 5, count, input.collect(&:to_a).inspect
          assert_equal [[[0, 9]], [[10, 19]], [[20, 29]], [[30, 39]], [[40, 44]]], input.collect(&:to_a)
        end
      end

      describe "#upload_integer_range_in_reverse_order" do
        before do
          input.slice_size = 10
        end

        it "handle single value" do
          count = input.upload_integer_range_in_reverse_order(1, 1)
          assert_equal 1, count, input.first.inspect
          assert_equal [[[1, 1]]], input.collect(&:to_a)
        end

        it "handle single range" do
          count = input.upload_integer_range_in_reverse_order(1, 10)
          assert_equal 1, count, input.first.inspect
          assert_equal [[[1, 10]]], input.collect(&:to_a)
        end

        it "handle longer range" do
          count = input.upload_integer_range_in_reverse_order(1, 11)
          assert_equal 2, count, input.collect(&:to_a).inspect
          assert_equal [[[2, 11]], [[1, 1]]], input.collect(&:to_a)
        end

        it "handle even longer range" do
          count = input.upload_integer_range_in_reverse_order(0, 44)
          assert_equal 5, count, input.collect(&:to_a).inspect
          assert_equal [[[35, 44]], [[25, 34]], [[15, 24]], [[5, 14]], [[0, 4]]], input.collect(&:to_a)
        end

        it "handle partial range" do
          count = input.upload_integer_range_in_reverse_order(5, 44)
          assert_equal 4, count, input.collect(&:to_a).inspect
          assert_equal [[[35, 44]], [[25, 34]], [[15, 24]], [[5, 14]]], input.collect(&:to_a)
        end
      end

      describe "#count" do
        it "count slices" do
          first = input.new(records: %w[hello world])
          input << first
          assert_equal 1, input.count

          second = input.new(records: %w[more records and more])
          input << second
          assert_equal 2, input.count

          third = input.new(records: %w[this is the last])
          input << third
          assert_equal 3, input.count

          assert_equal 3, input.queued.count
          assert_equal 0, input.running.count
          assert_equal 0, input.failed.count

          assert slice = input.next_slice(worker_name)
          assert_equal first.id, slice.id
          assert_equal true, slice.running?
          assert_equal 2, input.queued.count
          assert_equal 1, input.running.count
          assert_equal 0, input.failed.count

          assert slice = input.next_slice(worker_name)
          assert_equal second.id, slice.id
          assert_equal true, slice.running?
          assert_equal 1, input.queued.count
          assert_equal 2, input.running.count
          assert_equal 0, input.failed.count

          slice.fail!

          failed_slice = slice
          assert_equal 1, input.queued.count
          assert_equal 1, input.running.count
          assert_equal 1, input.failed.count

          assert slice = input.next_slice(worker_name)
          assert_equal third.id, slice.id
          assert_equal true, slice.running?
          assert_equal 0, input.queued.count
          assert_equal 2, input.running.count
          assert_equal 1, input.failed.count

          assert_nil input.next_slice(worker_name)
          assert_equal 0, input.queued.count
          assert_equal 2, input.running.count
          assert_equal 1, input.failed.count

          failed_slice.retry!
          assert_equal true, failed_slice.queued?
          assert_equal 1, input.queued.count
          assert_equal 2, input.running.count
          assert_equal 0, input.failed.count

          assert slice = input.next_slice(worker_name)
          assert_equal second.id, slice.id
          assert_equal true, slice.running?
          assert_equal 0, input.queued.count
          assert_equal 3, input.running.count
          assert_equal 0, input.failed.count
        end
      end

      describe "#each_failed_record" do
        it "return the correct failed record" do
          first = input.new(records: %w[hello world])
          first.start
          input << first
          assert_equal 1, input.count

          second = input.new(records: %w[more records and more])
          second.start
          input << second
          second.processing_record_number = 2
          assert_equal 2, input.count

          third = input.new(records: %w[this is the last])
          third.start
          input << third
          assert_equal 3, input.count

          exception = nil
          begin
            RocketJob.blah
          rescue StandardError => e
            exception = e
          end

          second.fail!(exception)
          second.save!
          count = 0
          input.each_failed_record do |record, slice|
            count += 1
            assert_equal "records", record
            assert_equal second.id, slice.id
            assert_equal second.to_a, slice.to_a
          end
          assert_equal 1, count, "No failed records returned"
        end
      end

      describe "#requeue_failed" do
        it "requeue failed slices" do
          first = input.new(records: %w[hello world])
          input << first
          assert_equal 1, input.count

          second = input.new(records: %w[more records and more])
          input << second
          second.processing_record_number = 2
          assert_equal 2, input.count

          third = input.new(records: %w[this is the last])
          input << third
          assert_equal 3, input.count

          exception = nil
          begin
            RocketJob.blah
          rescue StandardError => e
            exception = e
          end

          second.start
          second.fail!(exception)

          assert_equal 2, input.queued.count
          assert_equal 0, input.running.count
          assert_equal 1, input.failed.count

          assert_equal 1, input.requeue_failed.modified_count

          assert_equal 3, input.queued.count
          assert_equal 0, input.running.count
          assert_equal 0, input.failed.count
        end
      end

      describe "#requeue_running" do
        it "requeue running slices" do
          first = input.new(records: %w[hello world], worker_name: worker_name)
          first.start
          input << first
          assert_equal 1, input.count

          second = input.new(records: %w[more records and more], worker_name: worker_name)
          input << second
          assert_equal 2, input.count

          third = input.new(records: %w[this is the last], worker_name: "other")
          third.start
          input << third
          assert_equal 3, input.count

          assert_equal 1, input.queued.count
          assert_equal 2, input.running.count
          assert_equal 0, input.failed.count

          assert_equal 1, input.requeue_running(worker_name).modified_count

          assert_equal 2, input.queued.count
          assert_equal 1, input.running.count
          assert_equal 0, input.failed.count
        end
      end

      describe "#next_slice" do
        it "return the next available slice" do
          assert_nil input.next_slice(worker_name)

          first  = input.create!(records: %w[hello world])
          second = input.create!(records: %w[more records and more])
          third  = input.new(records: %w[this is the last])
          third.start!
          assert_equal 3, input.count

          assert slice = input.next_slice(worker_name)
          assert_equal collection_name, slice.collection_name
          assert_equal first.id, slice.id
          assert_equal true, slice.running?
          assert_equal worker_name, slice.worker_name
          slice = input.find(slice.id)
          assert_equal true, slice.running?
          assert_equal worker_name, slice.worker_name

          assert slice = input.next_slice(worker_name)
          assert_equal collection_name, slice.collection_name
          assert_equal second.id, slice.id
          assert_equal true, slice.running?
          assert_equal worker_name, slice.worker_name
          slice = input.find(slice.id)
          assert_equal true, slice.running?
          assert_equal worker_name, slice.worker_name

          assert_nil input.next_slice(worker_name)
          assert_equal 3, input.count
        end
      end
    end
  end
end
