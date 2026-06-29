require_relative "../test_helper"

module Server
  class ModelTest < Minitest::Test
    describe RocketJob::Server::Model do
      before do
        RocketJob::Server.destroy_all
      end

      after do
        RocketJob::Server.destroy_all
      end

      # Builds a persisted server in the supplied state, optionally with a stale heartbeat.
      def create_server(name:, state:, heartbeat_at: Time.now)
        server           = RocketJob::Server.new(name: name, state: state)
        server.heartbeat = RocketJob::Heartbeat.new(updated_at: heartbeat_at) if heartbeat_at
        server.save!
        server
      end

      describe ".counts_by_state" do
        it "is empty when there are no servers" do
          assert_equal({}, RocketJob::Server.counts_by_state)
        end

        it "returns the number of servers in each state" do
          create_server(name: "a", state: :running)
          create_server(name: "b", state: :running)
          create_server(name: "c", state: :paused)

          counts = RocketJob::Server.counts_by_state
          assert_equal 2, counts[:running]
          assert_equal 1, counts[:paused]
        end
      end

      describe "#zombie?" do
        it "is false for a server that is not running, stopping, or paused" do
          server = create_server(name: "starting", state: :starting)
          refute server.zombie?
        end

        it "is true for a running server with no heartbeat" do
          server = create_server(name: "no-beat", state: :running, heartbeat_at: nil)
          assert server.zombie?
        end

        it "is true for a running server whose heartbeat is stale" do
          server = create_server(name: "stale", state: :running, heartbeat_at: 5.minutes.ago)
          assert server.zombie?
        end

        it "is false for a running server with a recent heartbeat" do
          server = create_server(name: "fresh", state: :running, heartbeat_at: Time.now)
          refute server.zombie?
        end
      end

      describe ".zombies" do
        it "returns only servers with stale or missing heartbeats" do
          create_server(name: "alive", state: :running, heartbeat_at: Time.now)
          stale = create_server(name: "stale", state: :running, heartbeat_at: 5.minutes.ago)

          zombie_names = RocketJob::Server.zombies.collect(&:name)
          assert_includes zombie_names, stale.name
          refute_includes zombie_names, "alive"
        end
      end

      describe ".destroy_zombies" do
        it "destroys zombie servers and returns the count" do
          create_server(name: "alive", state: :running, heartbeat_at: Time.now)
          create_server(name: "stale", state: :running, heartbeat_at: 5.minutes.ago)

          assert_equal 1, RocketJob::Server.destroy_zombies
          assert_equal ["alive"], RocketJob::Server.all.collect(&:name)
        end
      end
    end
  end
end
