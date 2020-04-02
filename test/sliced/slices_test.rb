require_relative '../test_helper'

module Sliced
  class SlicesTest < Minitest::Test
    describe RocketJob::Sliced::Slices do
      let :collection_name do
        :'rocket_job.slices.test'
      end

      let :slices do
        RocketJob::Sliced::Slices.new(
          collection_name: collection_name,
          slice_size:      2
        )
      end

      before do
        slices.delete_all
        assert_equal 0, slices.count
        assert_equal collection_name, slices.collection_name

        @first = slices.create!(id: 1, records: %w[hello world])
        assert_equal collection_name, @first.collection_name
        assert_equal 1, slices.count

        @third = slices.new(id: 3, records: %w[this is the last])
        assert_equal collection_name, @third.collection_name
        @third.save!
        assert_equal 2, slices.count

        @second = slices.create(id: 2, records: %w[more records and more])
        assert @second.persisted?
        assert_equal collection_name, @second.collection_name
        assert_equal 3, slices.count
      end

      after do
        slices.drop
      end

      describe '#count' do
        it 'count slices' do
          assert_equal 3, slices.count
        end
      end

      describe '#each' do
        it 'count slices' do
          count = 0
          slices.each do |_slice|
            count += 1
          end
          assert_equal 3, count
        end

        it 'returns slices in id order' do
          count = 0
          id    = 1
          slices.each do |slice|
            assert_equal id, slice.id
            count += 1
            id    += 1
          end
          assert_equal 3, count
        end
      end

      describe '#first' do
        it 'return the first slice' do
          assert slice = slices.first
          assert_equal @first.id, slice.id
          assert_equal @first.to_a, slice.to_a
        end
      end

      describe '#last' do
        it 'return the last slice' do
          assert slice = slices.last
          assert_equal @third.id, slice.id
          assert_equal @third.to_a, slice.to_a
        end
      end

      describe '#<<' do
        it 'insert a slice' do
          count = slices.count
          slices << slices.new(records: [1, 2, 3, 4])
          assert_equal count + 1, slices.count
        end
        it 'insert an array of records as a new slice' do
          count = slices.count
          slices << [1, 2, 3, 4]
          assert_equal count + 1, slices.count
        end
      end

      describe '#insert' do
        it 'insert a slice' do
          count = slices.count
          slices.insert(slices.new(records: [1, 2, 3, 4]))
          assert_equal count + 1, slices.count
        end

        it 'insert an array of records as a new slice' do
          count = slices.count
          slices.insert([1, 2, 3, 4])
          assert_equal count + 1, slices.count
        end

        it 'insert a slice from an input slice' do
          input_slice = slices.new(records: [10, 20, 30])
          count       = slices.count
          slice       = slices.new(records: [1, 2, 3, 4])
          slices.insert(slice, input_slice)
          assert_equal count + 1, slices.count
          assert_equal input_slice.id, slice.id
          assert_equal input_slice.id, slices.last.id

          # Not throw exception on duplicate insert:
          slices.insert(slice, input_slice)
          assert_equal count + 1, slices.count
          assert_equal input_slice.id, slice.id
          assert_equal input_slice.id, slices.last.id
        end
      end

      describe '#find' do
        it 'find a slice by id' do
          count = slices.count
          slice = slices.new(records: [1, 2, 3, 4])
          slices.insert(slice)
          assert_equal count + 1, slices.count
          assert found_slice = slices.find(slice.id)
          assert_equal slice.id, found_slice.id
          assert_equal slice.to_a, found_slice.to_a
        end

        it 'find a slice by string id' do
          count = slices.count
          slice = slices.new(records: [1, 2, 3, 4])
          slices.insert(slice)
          assert_equal count + 1, slices.count
          assert found_slice = slices.find(slice.id.to_s)
          assert_equal slice.id, found_slice.id
          assert_equal slice.to_a, found_slice.to_a
        end
      end

      describe '#remove' do
        it 'remove a specific slice' do
          assert_equal 3, slices.count
          @second.destroy
          assert_equal 2, slices.count
          assert_equal @first.id, slices.first.id
          assert_equal @third.id, slices.last.id
        end
      end

      describe '#drop' do
        it 'drop this collection' do
          assert_equal 3, slices.count
          slices.drop
          assert_equal 0, slices.count
        end
      end

      describe '#delete_all' do
        it 'clear out all slices in this collection' do
          assert_equal 3, slices.count
          slices.delete_all
          assert_equal 0, slices.count
        end
      end

      describe '#exception' do
        it 'saves' do
          slice = slices.first
          assert_equal true, slice.save!
        end

        it 'fails' do
          exception = begin
            begin
              blah
            rescue StandardError => exc
              exc
            end
          end

          slice = slices.first
          slice.start!
          slice.reload
          assert_equal true, slice.fail!(exception)
          assert_equal 1, slice.failure_count
          assert slice.exception
          assert_equal exception.class.name, slice.exception.class_name
          assert_equal exception.message, slice.exception.message
          assert_equal exception.backtrace, slice.exception.backtrace
        end
      end
    end
  end
end
