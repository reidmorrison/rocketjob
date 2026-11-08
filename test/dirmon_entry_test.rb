require_relative "test_helper"

class DirmonEntryTest < Minitest::Test
  class TestJob < RocketJob::Job
    # Dirmon will store the filename in this property when starting the job
    field :upload_file_name, type: IOStreams::Path

    field :user_id, type: Integer

    def perform
      # Do something with the file name stored in :upload_file_name
    end
  end

  class BatchTestJob < RocketJob::Job
    include RocketJob::Batch

    # An input_category of :main is automatically created if none is specified

    # Collect output from this job
    output_category

    field :user_id, type: Integer

    def perform(row)
      row
    end
  end

  describe RocketJob::DirmonEntry do
    include SemanticLogger::Test::Minitest

    # Returns [Array<String>] the deprecation warnings that IOStreams reported while the block runs, with deprecation
    # warnings on, so that the tests do not print them.
    def iostreams_deprecation_warnings(&block)
      warnings = []
      previous = Warning[:deprecated]
      Warning[:deprecated] = true
      collect = lambda do |message, category: nil|
        warnings << message if category == :deprecated && IOStreams::Deprecation.warning?(message)
      end
      Warning.stub(:warn, collect, &block)
      warnings
    ensure
      Warning[:deprecated] = previous
    end

    let :archive_directory do
      "/tmp/archive_directory"
    end

    let :archive_path do
      IOStreams.path(archive_directory)
    end

    let :dirmon_entry do
      dirmon_entry = RocketJob::DirmonEntry.new(
        name:              "Test",
        job_class_name:    "DirmonEntryTest::TestJob",
        pattern:           "test/files/**",
        properties:        {user_id: 341},
        archive_directory: archive_directory
      )
      dirmon_entry.enable!

      assert_predicate dirmon_entry, :valid?, dirmon_entry.errors.messages.ai
      dirmon_entry
    end

    let :batch_dirmon_entry do
      dirmon_entry = RocketJob::DirmonEntry.new(
        name:              "Batch Test",
        job_class_name:    "DirmonEntryTest::BatchTestJob",
        pattern:           "test/files/**",
        properties:        {
          "user_id"           => 341,
          "input_categories"  => [
            {"format" => "csv"}
          ],
          "output_categories" => [
            {
              "format"  => "csv",
              "columns" => %w[first_name last_name]
            }
          ]
        },
        archive_directory: archive_directory
      )
      dirmon_entry.enable!

      assert_predicate dirmon_entry, :valid?, dirmon_entry.errors.messages.ai
      dirmon_entry
    end

    before do
      RocketJob::Jobs::DirmonJob.delete_all
      RocketJob::Jobs::UploadFileJob.delete_all
      RocketJob::DirmonEntry.delete_all
    end

    describe ".config" do
      it "support multiple databases" do
        assert_equal TEST_DATABASE, RocketJob::DirmonEntry.collection.database.name
      end
    end

    describe "#job_class" do
      describe "with a nil job_class_name" do
        it "return nil" do
          entry = RocketJob::DirmonEntry.new

          assert_nil entry.job_class
        end
      end

      describe "with an unknown job_class_name" do
        it "return nil" do
          entry = RocketJob::DirmonEntry.new(job_class_name: "FakeJobThatDoesNotExistAnyWhereIPromise")

          assert_nil entry.job_class
        end
      end

      describe "with a job_class_name that is not a Rocket Job" do
        it "is not valid" do
          %w[String Comparable RUBY_VERSION].each do |name|
            entry = RocketJob::DirmonEntry.new(job_class_name: name)

            refute_predicate entry, :valid?
            assert_equal ["Job #{name} must be defined and inherit from RocketJob::Job"], entry.errors[:job_class_name]
          end
        end
      end

      describe "with a valid job_class_name" do
        it "return job class" do
          entry = RocketJob::DirmonEntry.new(job_class_name: "RocketJob::Job")

          assert_equal RocketJob::Job, entry.job_class
          assert_equal 0, entry.properties.size
        end
      end
    end

    describe ".whitelist_paths" do
      it "default to []" do
        assert_equal [], RocketJob::DirmonEntry.whitelist_paths
      end
    end

    describe ".get_whitelist_paths" do
      after do
        RocketJob::DirmonEntry.whitelist_paths.each { |path| RocketJob::DirmonEntry.delete_whitelist_path(path) }
      end

      it "returns a copy that does not mutate the original" do
        path = RocketJob::DirmonEntry.add_whitelist_path("test/files")
        copy = RocketJob::DirmonEntry.get_whitelist_paths

        assert_equal [path], copy

        copy << "should-not-leak"

        refute_includes RocketJob::DirmonEntry.whitelist_paths, "should-not-leak"
      end
    end

    describe ".counts_by_state" do
      it "returns the number of entries in each state" do
        dirmon_entry # enabled and persisted

        failing = RocketJob::DirmonEntry.new(
          name:              "Failing",
          job_class_name:    "DirmonEntryTest::TestJob",
          pattern:           "test/other/**",
          properties:        {user_id: 341},
          archive_directory: archive_directory
        )
        failing.enable!
        failing.fail!("worker:1", "boom")

        counts = RocketJob::DirmonEntry.counts_by_state

        assert_equal 1, counts[:enabled]
        assert_equal 1, counts[:failed]
      end
    end

    describe ".add_whitelist_path" do
      after do
        RocketJob::DirmonEntry.whitelist_paths.each { |path| RocketJob::DirmonEntry.delete_whitelist_path(path) }
      end

      it "convert relative path to an absolute one" do
        path = IOStreams.path("test/files").realpath.to_s

        assert_equal path, RocketJob::DirmonEntry.add_whitelist_path("test/files")
        assert_equal [path], RocketJob::DirmonEntry.whitelist_paths
      end

      it "prevent duplicates" do
        path = IOStreams.path("test/files").realpath.to_s

        assert_equal path, RocketJob::DirmonEntry.add_whitelist_path("test/files")
        assert_equal path, RocketJob::DirmonEntry.add_whitelist_path("test/files")
        assert_equal path, RocketJob::DirmonEntry.add_whitelist_path(path)
        assert_equal [path], RocketJob::DirmonEntry.whitelist_paths
      end
    end

    describe "#pattern_display_name" do
      it "returns a local pattern as is" do
        assert_equal "test/files/**", dirmon_entry.pattern_display_name
      end

      it "leaves out the credentials of a url" do
        dirmon_entry.pattern = "sftp://user:secret@sftp.example.org/in/*.csv"

        assert_equal "sftp://sftp.example.org/in/*.csv", dirmon_entry.pattern_display_name
      end

      it "leaves out the query of a url pattern, which holds ssh options" do
        dirmon_entry.pattern = "sftp://user:secret@sftp.example.org/in/*.csv?password=other"

        warnings = iostreams_deprecation_warnings do
          assert_equal "sftp://sftp.example.org/in/*.csv", dirmon_entry.pattern_display_name
        end

        assert_equal 1, warnings.size, warnings
        assert_includes warnings.first, "its query is ignored"
        refute_includes warnings.first, "secret"
      end

      it "does not show a pattern with a query after pattern characters that a url cannot hold" do
        dirmon_entry.pattern = "sftp://user:secret@sftp.example.org/in/*.{csv,txt}?password=other"

        assert_equal "(not a valid path)", dirmon_entry.pattern_display_name
      end

      it "leaves out a pattern that is not a valid path, since its credentials cannot be found" do
        dirmon_entry.pattern = "sftp://user:secret@sftp.example.org:port/in/*.csv"

        assert_equal "(not a valid path)", dirmon_entry.pattern_display_name
      end

      it "returns nil without a pattern" do
        assert_nil RocketJob::DirmonEntry.new.pattern_display_name
      end

      it "leaves out the credentials of a url with pattern characters that a url cannot hold" do
        dirmon_entry.pattern = "sftp://user:secret@sftp.example.org/in/*.{csv,txt}"

        assert_equal "sftp://sftp.example.org/in/*.{csv,txt}", dirmon_entry.pattern_display_name
      end

      it "shows a url with a character class" do
        dirmon_entry.pattern = "sftp://sftp.example.org/in/[ab]*.csv"

        assert_equal "sftp://sftp.example.org/in/[ab]*.csv", dirmon_entry.pattern_display_name
      end

      it "shows a url whose pattern starts at the directory after its host" do
        dirmon_entry.pattern = "sftp://user:secret@sftp.example.org/{in,out}/*.csv"

        assert_equal "sftp://sftp.example.org/{in,out}/*.csv", dirmon_entry.pattern_display_name
      end

      [
        "sftp://user:se{cret@sftp.example.org/in/*.csv",
        "sftp://user:se{cret@sftp.example.org/in/data.csv",
        "sftp://user:se[cret@sftp.example.org/in/*.csv",
        "sftp://user:se[cret@sftp.example.org/in/data.csv",
        "sftp://user:se{cret@sftp.example.org/in/*.{csv,txt}",
        "sftp://us{er:secret@sftp.example.org/in/*.csv",
        "sftp://user:secret@sftp.ex{ample.org/in/*.csv"
      ].each do |pattern|
        it "leaves out a url whose user name, password or host holds a pattern character: #{pattern}" do
          dirmon_entry.pattern = pattern

          assert_equal "(not a valid path)", dirmon_entry.pattern_display_name
        end
      end
    end

    describe "#file_display_name" do
      # A file that IOStreams.each_child finds on an SFTP server, which it names without percent-encoding it.
      def sftp_file(name)
        IOStreams.path("sftp://user:secret@sftp.example.org/in").send(:child_path, name)
      end

      it "returns the url of a file whose name a url can hold, as it is" do
        assert_equal "sftp://sftp.example.org/in/data.csv.gz", dirmon_entry.file_display_name(sftp_file("data.csv.gz"))
        assert_equal "sftp://sftp.example.org/in/a-b_c~d;e=f.2026.csv",
                     dirmon_entry.file_display_name(sftp_file("a-b_c~d;e=f.2026.csv"))
      end

      it "returns the display name of a local file" do
        path = IOStreams.path("/var/sftp/in/data.csv")

        assert_equal "/var/sftp/in/data.csv", dirmon_entry.file_display_name(path)
      end

      it "returns the display name of a local file whose name a url cannot hold, as it is" do
        path = IOStreams.path("/var/sftp/in/données a+b%20[1]#c?d.csv")

        assert_equal "/var/sftp/in/données a+b%20[1]#c?d.csv", dirmon_entry.file_display_name(path)
      end

      it "returns the url of a file with its path percent-encoded, which IOStreams reads back as the same path" do
        warnings = iostreams_deprecation_warnings do
          {
            # IOStreams 2.2 cannot build a path from these urls unless they are encoded.
            "données.csv.gz"   => "sftp://sftp.example.org/in/donn%C3%A9es.csv.gz",
            "data[1].csv"      => "sftp://sftp.example.org/in/data%5B1%5D.csv",
            # It reads these as other names unless they are encoded.
            "a b.csv"          => "sftp://sftp.example.org/in/a%20b.csv",
            "a+b.csv"          => "sftp://sftp.example.org/in/a%2Bb.csv",
            "100%.csv"         => "sftp://sftp.example.org/in/100%25.csv",
            "a%20b.csv"        => "sftp://sftp.example.org/in/a%2520b.csv",
            "data#2026.csv.gz" => "sftp://sftp.example.org/in/data%232026.csv.gz",
            "data?2026.csv.gz" => "sftp://sftp.example.org/in/data%3F2026.csv.gz",
            "a+b%20#c d.csv"   => "sftp://sftp.example.org/in/a%2Bb%2520%23c%20d.csv",
            "données#1.csv"    => "sftp://sftp.example.org/in/donn%C3%A9es%231.csv"
          }.each_pair do |file_name, display_name|
            name = dirmon_entry.file_display_name(sftp_file(file_name))

            assert_equal display_name, name
            assert_predicate name, :valid_encoding?
            assert_equal "/in/#{file_name}", IOStreams.path(name).path
          end
        end

        assert_empty warnings
      end

      it "returns the url of a file with the directories in its path percent-encoded" do
        assert_equal "sftp://sftp.example.org/in/a%23b/r%C3%A9sum%C3%A9s/data.csv",
                     dirmon_entry.file_display_name(sftp_file("a#b/résumés/data.csv"))
      end

      it "keeps the port of the url, but not its credentials" do
        path = IOStreams.path("sftp://user:secret@sftp.example.org:2222/in").send(:child_path, "données.csv.gz")

        assert_equal "sftp://sftp.example.org:2222/in/donn%C3%A9es.csv.gz", dirmon_entry.file_display_name(path)
      end

      it "leaves out the credentials of a url that names the file" do
        path = IOStreams.path("sftp://user:secret@sftp.example.org/in/data.csv")

        assert_equal "sftp://sftp.example.org/in/data.csv", dirmon_entry.file_display_name(path)
      end

      it "returns a name that is valid UTF-8, for a file whose name is not" do
        name = dirmon_entry.file_display_name(sftp_file("caf\xE9.csv".b))

        assert_predicate name, :valid_encoding?
        assert_equal Encoding::UTF_8, name.encoding
        assert_equal "sftp://sftp.example.org/in/caf%E9.csv", name
        assert_equal "/in/caf\xE9.csv".b, IOStreams.path(name).path.b
      end

      it "returns a name that is valid UTF-8, for a file whose name is not, and that holds a #" do
        name = dirmon_entry.file_display_name(sftp_file("caf\xE9#1.csv".b))

        assert_predicate name, :valid_encoding?
        assert_equal "sftp://sftp.example.org/in/caf%E9%231.csv", name
        assert_equal "/in/caf\xE9#1.csv".b, IOStreams.path(name).path.b
      end

      it "returns a name that is valid UTF-8, for a local file whose name is not" do
        name = dirmon_entry.file_display_name(IOStreams.path("/var/sftp/in/caf\xE9.csv".b))

        assert_predicate name, :valid_encoding?
        assert_equal "/var/sftp/in/caf\\xE9.csv", name
      end

      it "returns a name that is shown as it is, see RocketJob.path_display_name" do
        name = dirmon_entry.file_display_name(sftp_file("données #1.csv"))

        assert_equal "sftp://sftp.example.org/in/donn%C3%A9es%20%231.csv", RocketJob.path_display_name(name)
      end
    end

    describe "#display_properties" do
      it "shows the paths in the properties without their credentials" do
        dirmon_entry.properties = {"user_id" => 341, "upload_file_name" => "sftp://user:secret@sftp.example.org/in.csv"}

        assert_equal({"user_id" => 341, "upload_file_name" => "sftp://sftp.example.org/in.csv"}, dirmon_entry.display_properties)
      end

      it "shows the paths in the categories of a batch job without their credentials" do
        batch_dirmon_entry.properties = {"input_categories" => [{"file_name" => "sftp://user:secret@sftp.example.org/in.csv"}]}

        assert_equal(
          {"input_categories" => [{"file_name" => "sftp://sftp.example.org/in.csv"}]},
          batch_dirmon_entry.display_properties
        )
      end

      it "shows the properties as stored when the job class is not defined" do
        dirmon_entry.job_class_name = "NoSuchJob"

        assert_equal dirmon_entry.properties, dirmon_entry.display_properties
      end

      it "shows the properties as stored when the job class is not a Rocket Job" do
        %w[String Comparable RUBY_VERSION].each do |name|
          dirmon_entry.job_class_name = name

          assert_equal dirmon_entry.properties, dirmon_entry.display_properties, name
        end
      end
    end

    describe "#archive_directory_display_name" do
      it "returns a local directory as is" do
        assert_equal archive_directory, dirmon_entry.archive_directory_display_name
      end

      it "leaves out the credentials of a url" do
        dirmon_entry.archive_directory = "sftp://user:secret@sftp.example.org/archive"

        assert_equal "sftp://sftp.example.org/archive", dirmon_entry.archive_directory_display_name
      end
    end

    describe "#replicate" do
      it "copies the settings, overridden by the supplied attributes" do
        entry = dirmon_entry.replicate(name: "Copy", pattern: "test/other/**")

        assert_predicate entry, :new_record?
        refute_equal dirmon_entry.id, entry.id
        assert_equal "Copy", entry.name
        assert_equal "test/other/**", entry.pattern
        assert_equal dirmon_entry.job_class_name, entry.job_class_name
        assert_equal dirmon_entry.archive_directory, entry.archive_directory
        assert_equal dirmon_entry.properties, entry.properties
        assert entry.save, entry.errors.messages.ai
      end

      it "does not copy what happened to the entry" do
        dirmon_entry.fail!("worker", "Storage unavailable")
        entry = dirmon_entry.replicate(name: "Copy", pattern: "test/other/**")

        assert_predicate entry, :pending?
        assert_nil entry.exception
      end

      it "is not valid until its name and pattern are changed, since each must be unique" do
        dirmon_entry.save!
        entry = dirmon_entry.replicate

        refute entry.save
        assert_includes entry.errors[:name], "has already been taken"
        assert_includes entry.errors[:pattern], "has already been taken"
      end

      it "copies only the settings of the entry" do
        dirmon_entry.fail("worker", "Storage unavailable")
        entry = dirmon_entry.replicate

        assert_equal %w[_id archive_directory job_class_name name pattern properties state],
                     entry.attributes.compact.keys.sort
      end

      it "does not share its properties with the entry" do
        entry = dirmon_entry.replicate
        entry.properties[:user_id] = 42

        assert_equal 341, dirmon_entry.properties[:user_id]
      end
    end

    describe "#fail!" do
      it "fail with message" do
        dirmon_entry.fail!("myworker:2323", "oh no")

        assert_predicate dirmon_entry, :failed?
        assert_equal "RocketJob::DirmonEntryException", dirmon_entry.exception.class_name
        assert_equal "oh no", dirmon_entry.exception.message
      end

      it "fail with exception" do
        exception = nil
        begin
          RocketJob.blah
        rescue Exception => e
          exception = e
        end
        dirmon_entry.fail!("myworker:2323", exception)

        assert_predicate dirmon_entry, :failed?
        assert_equal exception.class.name.to_s, dirmon_entry.exception.class_name
        assert_includes dirmon_entry.exception.message, "undefined method", dirmon_entry.attributes.inspect
      end
    end

    describe "#validate" do
      it "strip_whitespace" do
        dirmon_entry.pattern           = " test/files/*"
        dirmon_entry.archive_directory = " test/archive/ "

        assert_predicate dirmon_entry, :valid?
        assert_equal "test/files/*", dirmon_entry.pattern
        assert_equal "test/archive/", dirmon_entry.archive_directory
      end

      describe "pattern" do
        it "present" do
          dirmon_entry.pattern = nil

          refute_predicate dirmon_entry, :valid?
          assert_equal ["can't be blank"], dirmon_entry.errors[:pattern], dirmon_entry.errors.messages.ai
        end
      end

      describe "job_class_name" do
        it "ensure presence" do
          dirmon_entry.job_class_name = nil

          refute_predicate dirmon_entry, :valid?
          assert_equal ["can't be blank"], dirmon_entry.errors[:job_class_name], dirmon_entry.errors.messages.ai
        end

        it "is a RocketJob::Job" do
          dirmon_entry.job_class_name = "String"

          refute_predicate dirmon_entry, :valid?
          assert_equal ["Job String must be defined and inherit from RocketJob::Job"], dirmon_entry.errors[:job_class_name], dirmon_entry.errors.messages.ai
        end

        it "is invalid" do
          dirmon_entry.job_class_name = "Blah"

          refute_predicate dirmon_entry, :valid?
          assert_equal ["Job Blah must be defined and inherit from RocketJob::Job"], dirmon_entry.errors[:job_class_name], dirmon_entry.errors.messages.ai
        end
      end

      describe "properties" do
        it "are valid" do
          dirmon_entry.properties = {user_id: 123}

          assert_predicate dirmon_entry, :valid?, dirmon_entry.errors.messages.ai
        end

        it "not valid" do
          dirmon_entry.properties = {blah: 123}

          refute_predicate dirmon_entry, :valid?
          assert_equal ["Unknown Property: Attempted to set a value for :blah which is not allowed on the job DirmonEntryTest::TestJob"], dirmon_entry.errors[:properties], dirmon_entry.errors.messages.ai
        end

        it "allows known category properties" do
          dirmon_entry.properties = {output_categories: [{name: "main"}]}

          assert_predicate dirmon_entry, :valid?, dirmon_entry.errors.messages.ai
        end

        it "rejects unknown category properties" do
          dirmon_entry.properties = {output_categories: [{not_a_category_field: 1}]}

          refute_predicate dirmon_entry, :valid?
          assert(dirmon_entry.errors[:properties].any? { |m| m.include?("not_a_category_field") },
                 dirmon_entry.errors.messages.ai)
        end
      end
    end

    describe "with valid entry" do
      let :file do
        file = Tempfile.new("archive")
        File.write(file.path, "Hello World")
        file
      end

      let :file_name do
        file.path
      end

      let :iopath do
        IOStreams.path(file_name)
      end

      after do
        file.delete
        RocketJob::Jobs::DirmonJob.delete_all
      end

      describe "#each" do
        it "without archive path" do
          dirmon_entry.archive_directory = nil
          files                          = []
          dirmon_entry.each { |file_name| files << file_name }

          assert_nil dirmon_entry.archive_directory
          assert_equal 1, files.count
          assert_equal IOStreams.path("test/files/text.txt").realpath, files.first
        end

        it "with archive path" do
          files = []
          dirmon_entry.each { |file_name| files << file_name }

          assert_equal 1, files.count
          assert_equal IOStreams.path("test/files/text.txt").realpath, files.first
        end

        it "with case-insensitive pattern" do
          skip "Failing on Github Actions right now" if ENV["GITHUB_ACTIONS"]

          dirmon_entry.pattern = "test/files/**/*.TxT"
          files                = []
          dirmon_entry.each { |file_name| files << file_name }

          assert_equal 1, files.count, -> { IOStreams.path("test/files").children.ai }
          assert_equal IOStreams.path("test/files/text.txt").realpath, files.first
        end

        it "reads paths inside of the whitelist" do
          dirmon_entry.archive_directory = nil
          files                          = []
          dirmon_entry.stub(:whitelist_paths, [IOStreams.path("test/files").realpath.to_s]) do
            dirmon_entry.each { |file_name| files << file_name }
          end

          assert_nil dirmon_entry.archive_directory
          assert_equal 1, files.count
          assert_equal IOStreams.path("test/files/text.txt").realpath, files.first
        end

        it "skips paths outside of the whitelist" do
          dirmon_entry.archive_directory = nil
          files                          = []
          dirmon_entry.stub(:whitelist_paths, [IOStreams.path("test/config").realpath.to_s]) do
            dirmon_entry.each { |file_name| files << file_name }
          end

          assert_nil dirmon_entry.archive_directory
          assert_equal 0, files.count
        end

        it "logs a file outside of the whitelist without the credentials in its url" do
          sftp   = IOStreams.path("sftp://jack:secret@sftp.example.org/files/data.csv")
          events = semantic_logger_events do
            IOStreams.stub(:each_child, ->(_pattern, &block) { block.call(sftp) }) do
              dirmon_entry.stub(:whitelist_paths, ["/var/sftp"]) do
                dirmon_entry.each { |_path| flunk("Must skip a file outside of the whitelist") }
              end
            end
          end

          assert(events.any? { |event| event.message.include?("sftp://sftp.example.org/files/data.csv") })
          refute(events.any? { |event| "#{event.message}#{event.payload}".include?("secret") })
        end

        it "skips a file that is not writable, and logs it without the credentials in its url" do
          sftp = IOStreams.path("sftp://jack:secret@sftp.example.org/files/data.csv")
          sftp.define_singleton_method(:writable?) { false }
          events = semantic_logger_events do
            IOStreams.stub(:each_child, ->(_pattern, &block) { block.call(sftp) }) do
              dirmon_entry.each { |_path| flunk("Must skip a file that is not writable") }
            end
          end

          assert(
            events.any? do |event|
              event.message.include?("Skipping file: sftp://sftp.example.org/files/data.csv since it is not writable")
            end
          )
          refute(events.any? { |event| "#{event.message}#{event.payload}".include?("secret") })
        end
      end

      describe "#later" do
        it "enqueues job" do
          job = dirmon_entry.later(iopath)

          assert created_job = RocketJob::Jobs::UploadFileJob.last
          assert_equal job.id, created_job.id
          assert_predicate job, :queued?
        end

        it "sets attributes" do
          job = dirmon_entry.later(iopath)

          upload_file_name = IOStreams.path(archive_directory).join("#{job.job_id}_#{File.basename(file_name)}").to_s

          assert_equal dirmon_entry.job_class_name, job.job_class_name
          assert_equal dirmon_entry.properties, job.properties
          assert_equal upload_file_name, job.upload_file_name.to_s
          assert_equal "#{dirmon_entry.name}: #{iopath.basename}", job.description
          assert_equal iopath.display_name, job.original_file_name
          assert job.job_id
        end

        it "records and logs the original file name without the credentials in its url" do
          sftp = IOStreams.path("sftp://jack:secret@sftp.example.org/files/data.csv")
          sftp.define_singleton_method(:move_to) do |target|
            target.write("data")
            target
          end

          job    = nil
          events = semantic_logger_events { job = dirmon_entry.later(sftp) }

          assert_equal "sftp://sftp.example.org/files/data.csv", job.original_file_name
          refute(events.any? { |event| "#{event.message}#{event.payload}".include?("secret") })
        end

        it "records the original file name with its extensions, when its display name leaves them out" do
          sftp = IOStreams.path("sftp://jack:secret@sftp.example.org/files").send(:child_path, "data#2026.csv.gz")
          sftp.define_singleton_method(:move_to) do |target|
            target.write("data")
            target
          end

          job = dirmon_entry.later(sftp)

          assert_equal "sftp://sftp.example.org/files/data%232026.csv.gz", job.original_file_name
          assert_equal "#{dirmon_entry.name}: data#2026.csv.gz", job.description
        end

        it "records the original file name percent-encoded, when IOStreams cannot read its url back" do
          sftp = IOStreams.path("sftp://jack:secret@sftp.example.org/files").send(:child_path, "données.csv.gz")
          sftp.define_singleton_method(:move_to) do |target|
            target.write("data")
            target
          end

          job = dirmon_entry.later(sftp)

          assert_equal "sftp://sftp.example.org/files/donn%C3%A9es.csv.gz", job.original_file_name
          assert_equal "/files/données.csv.gz", IOStreams.path(job.original_file_name).path
          assert_equal "#{dirmon_entry.name}: données.csv.gz", job.description
        end

        it "enqueues batch job" do
          job = batch_dirmon_entry.later(iopath)

          assert created_job = RocketJob::Jobs::UploadFileJob.last
          assert_equal job.id, created_job.id
          assert_predicate job, :queued?
        end

        it "sets batch attributes" do
          job = batch_dirmon_entry.later(iopath)

          upload_file_name = IOStreams.path(archive_directory).join("#{job.job_id}_#{File.basename(file_name)}").to_s

          assert_equal batch_dirmon_entry.job_class_name, job.job_class_name
          assert_equal batch_dirmon_entry.properties, job.properties
          assert_equal upload_file_name, job.upload_file_name.to_s
          assert_equal "#{batch_dirmon_entry.name}: #{iopath.basename}", job.description
          assert_equal iopath.display_name, job.original_file_name
          assert job.job_id
        end
      end

      describe "#archive_iopath" do
        it "with fully qualified archive directory" do
          assert_equal archive_path.to_s, dirmon_entry.send(:archive_iopath, iopath).to_s
        end

        describe "with relative" do
          let :archive_directory do
            "my_archive/files"
          end

          it "archive directory" do
            archive_dir = iopath.directory.join(archive_directory)

            assert_equal archive_dir.to_s, dirmon_entry.send(:archive_iopath, iopath).to_s
          end
        end

        it "has a default archive directory" do
          e = RocketJob::DirmonEntry.new(
            pattern:        "test/files/**/*",
            job_class_name: "RocketJob::Jobs::DirmonJob"
          )

          assert_equal "archive", e.archive_directory
        end
      end
    end
  end
end
