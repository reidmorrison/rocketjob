require_relative "test_helper"
require "tmpdir"

class CLITest < Minitest::Test
  describe RocketJob::CLI do
    describe "--name" do
      it "sets the name of this server" do
        previous = RocketJob::Config.server_name
        RocketJob::CLI.new(["--name", "worker1"])

        assert_equal "worker1", RocketJob::Config.server_name
      ensure
        RocketJob::Config.server_name = previous
      end
    end

    describe "#write_pidfile" do
      it "writes the id of this process" do
        pidfile = File.join(Dir.tmpdir, "rocketjob_cli_test_#{Process.pid}.pid")
        RocketJob::CLI.new(["--pidfile", pidfile]).write_pidfile

        assert_equal "#{Process.pid}\n", File.read(pidfile)
      ensure
        FileUtils.rm_f(pidfile)
      end
    end
  end
end
