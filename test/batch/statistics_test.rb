require_relative '../test_helper'

module Batch
  class StatisticsTest < Minitest::Test
    # This job adds each callback as they run into an array
    class BatchSlicesJob < RocketJob::Job
      include RocketJob::Batch
      include RocketJob::Batch::Statistics

      field :header, type: String

      before_batch :process_first_slice

      def perform(record)
        if record % 2 == 0
          statistics_inc('even')
        else
          statistics_inc('odd')
        end
      end

      private

      # Also test that header can be extracted in a before_batch
      def process_first_slice
        work_first_slice do |line|
          if header.nil?
            self.header = line
          else
            perform(line)
          end
        end
      end
    end

    # This job adds each callback as they run into an array
    class HashStatsJob < RocketJob::Job
      include RocketJob::Batch
      include RocketJob::Batch::Statistics

      def perform(record)
        if record % 2 == 0
          statistics_inc(even: 1)
        else
          statistics_inc(odd: 1, 'and.more' => 2)
        end
      end
    end

    describe RocketJob::Batch::Statistics::Stats do
      describe '#inc_key' do
        describe 'in_memory' do
          let :stats do
            RocketJob::Batch::Statistics::Stats.new(Hash.new(0))
          end

          before do
            assert_nil stats.stats
            assert_equal({}, stats.in_memory)
          end

          it 'handles empty key' do
            stats.inc_key('')
            assert_nil stats.stats
            assert_equal({}, stats.in_memory)
          end

          it 'handles nil key' do
            stats.inc_key(nil)
            assert_nil stats.stats
            assert_equal({}, stats.in_memory)
          end

          it 'increments simple key' do
            stats.inc_key(:user_count)
            assert_nil stats.stats
            assert_equal({'user_count' => 1}, stats.in_memory)
          end

          it 'increments nested key' do
            stats.inc_key('us.na.user.count')
            assert_nil stats.stats
            assert_equal({"us" => {"na" => {"user" => {"count" => 1}}}}, stats.in_memory)
          end
        end

        describe 'stored' do
          let :stats do
            RocketJob::Batch::Statistics::Stats.new
          end

          before do
            assert_nil stats.in_memory
            assert_equal({}, stats.stats)
          end

          it 'handles empty key' do
            stats.inc_key('')
            assert_nil stats.in_memory
            assert_equal({}, stats.stats)
          end

          it 'handles nil key' do
            stats.inc_key(nil)
            assert_nil stats.in_memory
            assert_equal({}, stats.stats)
          end

          it 'increments simple key' do
            stats.inc_key(:user_count)
            assert_nil stats.in_memory
            assert_equal({'statistics.user_count' => 1}, stats.stats)
          end

          it 'increments nested key' do
            stats.inc_key('us.na.user.count')
            assert_nil stats.in_memory
            assert_equal({'statistics.us.na.user.count' => 1}, stats.stats)
          end
        end
      end

      describe '#inc' do
        describe 'in_memory' do
          let :stats do
            RocketJob::Batch::Statistics::Stats.new(Hash.new(0))
          end

          before do
            assert_nil stats.stats
            assert_equal({}, stats.in_memory)
          end

          it 'handles empty key' do
            stats.inc('' => 21)
            assert_nil stats.stats
            assert_equal({}, stats.in_memory)
          end

          it 'handles nil key' do
            stats.inc(nil => 24)
            assert_nil stats.stats
            assert_equal({}, stats.in_memory)
          end

          it 'increments simple key' do
            stats.inc(user_count: 24)
            assert_nil stats.stats
            assert_equal({'user_count' => 24}, stats.in_memory)
          end

          it 'increments nested key' do
            stats.inc('us.na.user.count' => 23)
            assert_nil stats.stats
            assert_equal({"us" => {"na" => {"user" => {"count" => 23}}}}, stats.in_memory)
          end
        end

        describe 'stored' do
          let :stats do
            RocketJob::Batch::Statistics::Stats.new
          end

          before do
            assert_nil stats.in_memory
            assert_equal({}, stats.stats)
          end

          it 'handles empty key' do
            stats.inc('' => 21)
            assert_nil stats.in_memory
            assert_equal({}, stats.stats)
          end

          it 'handles nil key' do
            stats.inc(nil => 21)
            assert_nil stats.in_memory
            assert_equal({}, stats.stats)
          end

          it 'increments simple key' do
            stats.inc(user_count: 24)
            assert_nil stats.in_memory
            assert_equal({'statistics.user_count' => 24}, stats.stats)
          end

          it 'increments nested key' do
            stats.inc('us.na.user.count' => 23)
            assert_nil stats.in_memory
            assert_equal({'statistics.us.na.user.count' => 23}, stats.stats)
          end
        end
      end
    end

    describe RocketJob::Batch::Statistics do
      after do
        @job.destroy if @job && !@job.new_record?
      end

      describe '#statistics_inc' do
        it 'in memory model' do
          records = 7
          @job    = BatchSlicesJob.new(slice_size: 4)
          @job.upload do |stream|
            stream << 'header line'
            records.times.each { |i| stream << i }
          end
          @job.perform_now
          assert @job.completed?, @job.attributes.ai
          assert_equal ['even', 'odd'], @job.statistics.keys.sort
          assert_equal 4, @job.statistics['even'], @job.statistics.ai
          assert_equal 3, @job.statistics['odd'], @job.statistics.ai
          assert_equal 'header line', @job.header
        end

        it 'persisted model' do
          records = 7
          @job    = BatchSlicesJob.new(slice_size: 4)
          @job.upload do |stream|
            stream << 'header line'
            records.times.each { |i| stream << i }
          end
          @job.save!
          @job.perform_now
          assert @job.completed?, @job.attributes.ai
          assert_equal ['even', 'odd'], @job.statistics.keys.sort
          assert_equal 4, @job.statistics['even'], @job.statistics.ai
          assert_equal 3, @job.statistics['odd'], @job.statistics.ai
          assert_equal 'header line', @job.header
          @job.reload
          assert_equal ['even', 'odd'], @job.statistics.keys.sort
          assert_equal 4, @job.statistics['even'], @job.statistics.ai
          assert_equal 3, @job.statistics['odd'], @job.statistics.ai
        end

        it 'handles hash in memory model' do
          records = 7
          @job    = HashStatsJob.new(slice_size: 4)
          @job.upload do |stream|
            records.times.each { |i| stream << i }
          end
          @job.perform_now
          assert @job.completed?, @job.attributes.ai
          assert_equal ['and', 'even', 'odd'], @job.statistics.keys.sort
          assert_equal 4, @job.statistics['even'], @job.statistics.ai
          assert_equal 3, @job.statistics['odd'], @job.statistics.ai
          assert_equal({'more' => 6}, @job.statistics['and'], @job.statistics.ai)
        end

        it 'handles hash in stored model' do
          records = 7
          @job    = HashStatsJob.new(slice_size: 4)
          @job.upload do |stream|
            records.times.each { |i| stream << i }
          end
          @job.save!
          @job.perform_now
          assert @job.completed?, @job.attributes.ai
          assert_equal ['and', 'even', 'odd'], @job.statistics.keys.sort
          assert_equal 4, @job.statistics['even'], @job.statistics.ai
          assert_equal 3, @job.statistics['odd'], @job.statistics.ai
          assert_equal({'more' => 6}, @job.statistics['and'], @job.statistics.ai)
        end
      end
    end
  end
end
