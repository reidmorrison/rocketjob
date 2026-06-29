require_relative "../test_helper"

module Plugins
  class DocumentTest < Minitest::Test
    class DocumentJob < RocketJob::Job
      field :data, type: Hash

      def perform
        data
      end
    end

    describe RocketJob::Plugins::Document do
      before do
        RocketJob::Job.destroy_all
      end

      after do
        RocketJob::Job.destroy_all
      end

      describe ".first / .last" do
        it "returns nil when there are no documents" do
          assert_nil DocumentJob.first
          assert_nil DocumentJob.last
        end

        it "orders by _id ascending and descending" do
          first_job = DocumentJob.create!(description: "first")
          last_job  = DocumentJob.create!(description: "last")

          assert_equal first_job.id, DocumentJob.first.id
          assert_equal last_job.id, DocumentJob.last.id
        end
      end

      describe "#find_and_update" do
        it "applies changes and returns the reloaded document" do
          job = DocumentJob.create!(description: "before")

          result = job.send(:find_and_update, "description" => "after")

          assert_same job, result
          assert_equal "after", job.description
          # The change is persisted in the database.
          assert_equal "after", DocumentJob.find(job.id).description
        end

        it "loads concurrent changes made on the server" do
          job = DocumentJob.create!(description: "original", priority: 10)

          # Simulate another process updating a different attribute.
          DocumentJob.collection.find(_id: job.id).update_one("$set" => {"priority" => 99})

          job.send(:find_and_update, "description" => "updated")

          assert_equal "updated", job.description
          assert_equal 99, job.priority
        end

        it "raises DocumentNotFound when the document no longer exists" do
          job = DocumentJob.create!(description: "gone")
          job.destroy

          assert_raises(Mongoid::Errors::DocumentNotFound) do
            job.send(:find_and_update, "description" => "nope")
          end
        end
      end
    end
  end
end
