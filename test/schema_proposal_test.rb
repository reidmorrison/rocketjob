require_relative "test_helper"

class SchemaProposalTest < Minitest::Test
  class ProposalJob < RocketJob::Job
    include RocketJob::Batch

    self.destroy_on_complete = false

    def perform(record)
      record
    end
  end

  # Defines a category with deprecated options, without the deprecation warning, as a saved category holds them.
  class DeprecatedJob < RocketJob::Job
    include RocketJob::Batch

    self.destroy_on_complete = false

    def perform(record)
      record
    end
  end

  # A header with mixed case, spaces and punctuation, and a column that allowed_columns leaves out.
  CSV = "First Name,Last-Name,Zip Code,Extra\nJack,Jones,12345,x\nJill,,54321,y\n".freeze

  describe RocketJob::SchemaProposal do
    def input(**)
      RocketJob::Category::Input.new(**)
    end

    def proposal(category)
      category.schema_proposal("ProposalJob, #{category.class.name.demodulize.downcase} category main")
    end

    # Returns [Array<String>] how the proposal for the category reads the data differently from the category, written
    # to a file with the extension of the supplied file name.
    def dry_run(category, data, file_name: "people.csv")
      IOStreams.temp_file("schema_proposal", File.extname(file_name)) do |path|
        path.write(data)
        proposal(category).dry_run(path.to_s)
      end
    end

    before do
      RocketJob::Job.delete_all
      RocketJob::DirmonEntry.delete_all
    end

    describe "an input category" do
      it "proposes nothing without a deprecated option" do
        assert_nil proposal(input(format: :csv))
        assert_nil proposal(input(format: :csv, schema: {"fields" => [{"name" => "name"}]}))
      end

      it "replaces allowed_columns with the fields they allow, keyed as before" do
        category = input(format: :csv, allowed_columns: %w[first_name zip_code])

        assert_equal(
          {
            "allowed_columns" => nil,
            "schema"          => {
              "fieldsMatch" => "superset",
              "fields"      => [{"name" => "first_name"}, {"name" => "zip_code"}],
              "keyType"     => "cleansed"
            }
          },
          proposal(category).changes
        )
      end

      it "reads a file as allowed_columns with skip_unknown did" do
        category = input(format: :csv, allowed_columns: %w[first_name last_name zip_code], skip_unknown: true)

        assert_equal "partial", proposal(category).schema["fieldsMatch"]
        assert_empty dry_run(category, CSV)
      end

      it "reads a file as required_columns with allowed_columns did" do
        category = input(format: :csv, allowed_columns: %w[first_name last_name zip_code], required_columns: %w[zip_code],
                         skip_unknown: true)

        assert_includes proposal(category).schema["fields"],
                        {"name" => "zip_code", "constraints" => {"required" => true}, "allowBlank" => true}
        assert_empty dry_run(category, CSV)
      end

      it "keeps every other column for required_columns alone, after the fields" do
        category = input(format: :csv, required_columns: %w[zip_code])
        schema   = proposal(category).schema

        assert_equal %w[subset keep cleansed], schema.values_at("fieldsMatch", "extraColumns", "keyType")
        assert_equal [
          "Record 1: keys in another order: [\"zip_code\", \"first_name\", \"last_name\", \"extra\"] rather than " \
          "[\"first_name\", \"last_name\", \"zip_code\", \"extra\"]",
          "Record 2: keys in another order: [\"zip_code\", \"first_name\", \"last_name\", \"extra\"] rather than " \
          "[\"first_name\", \"last_name\", \"zip_code\", \"extra\"]"
        ], dry_run(category, CSV)
      end

      it "reads a file as header_cleanser :none did, keeping every column as it is named" do
        category = input(format: :csv, header_cleanser: :none)

        assert_equal({"fieldsMatch" => "subset", "extraColumns" => "keep", "fields" => []}, proposal(category).schema)
        assert_empty dry_run(category, CSV)
      end

      it "removes the restrictions that header_cleanser :none ignored" do
        category = input(format: :csv, header_cleanser: :none, allowed_columns: %w[first_name], skip_unknown: true)
        proposal = proposal(category)

        assert_equal({"fieldsMatch" => "subset", "extraColumns" => "keep", "fields" => []}, proposal.schema)
        assert_match(/7.0 did not apply allowed_columns, skip_unknown with header_cleanser :none/, proposal.notes.first)
        assert_empty dry_run(category, CSV)
      end

      it "reads a file without a header row as its columns did, uncleansed, skipping a nil column" do
        category = input(format: :csv, columns: ["Name", nil, "Zip Code"])

        assert_equal(
          {
            "header" => false,
            "fields" => [{"name" => "Name"}, {"name" => "column_2", "skip" => true}, {"name" => "Zip Code"}]
          },
          proposal(category).schema
        )
        assert_empty dry_run(category, "Jack,x,12345\nJill,y,54321\n")
      end

      it "removes the restrictions that the columns of a file without a header row ignored" do
        category = input(format: :csv, columns: %w[name zip extra], allowed_columns: %w[name zip], skip_unknown: true)
        proposal = proposal(category)

        assert_equal(%w[name zip extra], proposal.schema["fields"].map { |field| field["name"] })
        assert_match(/to the columns of a file without a header row/, proposal.notes.first)
        assert_empty dry_run(category, "Jack,12345,x\nJill,54321,y\n")
      end

      it "removes the restrictions that JSON records ignored, without a schema" do
        category = input(format: :json, allowed_columns: %w[first_name], required_columns: %w[missing])
        proposal = proposal(category)

        assert_nil proposal.schema
        assert_equal({"allowed_columns" => nil, "required_columns" => nil}, proposal.changes)
        assert_match(/7.0 did not apply allowed_columns, required_columns to JSON records/, proposal.notes.first)
        assert_empty dry_run(category, %({"First Name":"Jack","Zip Code":"12345"}\n), file_name: "people.json")
      end

      it "says that format :auto restricted CSV files but not JSON files" do
        proposal = proposal(input(format: :auto, allowed_columns: %w[first_name], skip_unknown: true))

        assert(proposal.notes.any? { |note| note.start_with?("With format :auto, 7.0 applied") })
      end

      it "finds, with a dry run, a field that 7.0 cleansed without its letters that are not ASCII" do
        category = input(format: :csv, allowed_columns: %w[prnom zip_code], skip_unknown: true)

        assert(proposal(category).notes.any? { |note| note.include?("such as prnom for Prénom") })
        assert_equal ["Record 1: keys no longer read: [\"prnom\"]"], dry_run(category, "Prénom,Zip Code\nJosé,12345\n")
      end

      it "removes skip_unknown, which did nothing without allowed_columns" do
        proposal = proposal(input(format: :csv, skip_unknown: true))

        assert_equal({"skip_unknown" => false}, proposal.changes)
      end

      it "removes the column options of a category without a format, which had no effect" do
        proposal = proposal(input(allowed_columns: %w[a]))

        assert_equal({"allowed_columns" => nil}, proposal.changes)
        assert_match(/Without a format/, proposal.notes.first)
      end

      it "replaces the :array mode with :line" do
        assert_equal({"mode" => :line}, proposal(input(format: :csv, mode: :array)).changes)
      end

      it "replaces the :hash mode with a schema by validate_rows, since it parsed every line when a file was uploaded" do
        category = input(format: :csv, mode: :hash, schema: {"fields" => [{"name" => "name"}]})

        assert_equal({"mode" => :line, "validate_rows" => true}, proposal(category).changes)
      end

      it "replaces the :hash mode without a schema by :line, since it had no effect" do
        assert_equal({"mode" => :line}, proposal(input(format: :csv, mode: :hash)).changes)
      end

      it "keeps validate_rows when it is set with the :hash mode" do
        category = input(format: :csv, mode: :hash, validate_rows: false, schema: {"fields" => [{"name" => "name"}]})

        assert_equal({"mode" => :line}, proposal(category).changes)
      end

      it "replaces a fixed width layout, reading its files as it did" do
        layout   = {layout: [{size: 4, key: "name"}, {size: 5, key: "zip", type: :integer}]}
        category = input(format: :fixed, format_options: layout)

        assert_equal(
          [{"name" => "name", "type" => "string", "width" => 4, "truncate" => true},
           {"name" => "zip", "type" => "integer", "width" => 5}],
          proposal(category).schema["fields"]
        )
        assert_empty dry_run(category, "Jack12345\nJill54321\n", file_name: "people.txt")
      end

      it "keeps the Symbol keys of a layout" do
        category = input(format: :fixed, format_options: {layout: [{size: 4, key: :name}, {size: 5, key: :zip}]})

        assert_equal "symbol", proposal(category).schema["keyType"]
        assert_empty dry_run(category, "Jack12345\n", file_name: "people.txt")
      end

      it "skips the fields of a layout that its columns leave out" do
        layout   = {layout: [{size: 4, key: "name"}, {size: 5, key: "zip"}]}
        category = input(format: :fixed, format_options: layout, columns: %w[name])

        assert_equal({"name" => "zip", "width" => 5, "skip" => true}, proposal(category).schema["fields"].last)
        assert_empty dry_run(category, "Jack12345\n", file_name: "people.txt")
      end

      it "says why a layout cannot be translated, and changes nothing" do
        category = input(format: :fixed, format_options: {layout: [{size: 2, key: :a}, {size: 2, key: :a}]})
        proposal = proposal(category)

        assert_match(/More than one column of the layout has the key :a/, proposal.error)
        assert_empty proposal.changes
      end

      it "proposes for the columns of JSON records, which 7.0 narrowed the records to" do
        proposal = proposal(input(format: :json, columns: %w[first_name zip]))

        assert_equal({"fieldsMatch" => "partial", "fields" => [{"name" => "first_name"}, {"name" => "zip"}]},
                     proposal.schema)
        assert_match(/7.0 narrowed each record to its columns, matching its keys exactly/, proposal.notes.first)
      end

      it "removes the restrictions of Hash records, which 7.0 did not apply" do
        proposal = proposal(input(format: :hash, allowed_columns: %w[a]))

        assert_nil proposal.schema
        assert_match(/to Hash records/, proposal.notes.first)
      end

      it "keys the records of a layout with Symbol keys and columns by Strings, as 7.0 did" do
        category = input(format: :fixed, format_options: {layout: [{size: 4, key: :name}, {size: 5, key: :zip}]},
                         columns: %w[name])

        assert_nil proposal(category).schema["keyType"]
        assert_empty dry_run(category, "Jack12345\n", file_name: "people.txt")
      end

      it "says why a layout of a format other than fixed width cannot be translated" do
        proposal = proposal(input(format: :csv, format_options: {truncate: false}))

        assert proposal.error
        assert_empty proposal.changes
      end

      it "only removes the deprecated options of a category that already has a schema" do
        category = input(format: :csv, schema: {"fields" => [{"name" => "zip", "type" => "integer"}]})
        category.header_cleanser = :none
        proposal = proposal(category)

        assert_equal({"header_cleanser" => :default}, proposal.changes)
        assert_match(/already has a schema/, proposal.notes.first)
      end

      it "keeps the header row that a saved job's own upload read" do
        category = input(format: :csv, columns: %w[first_name zip_code])

        assert_nil category.schema_proposal("ProposalJob 1 (queued)", defined: input(format: :csv), uploaded: true)
      end

      it "drops columns copied from an earlier upload, when the job class sets none" do
        category = input(format: :csv, columns: %w[first_name zip_code])
        proposal = category.schema_proposal("ProposalJob 1 (queued), input category main", defined: input(format: :csv))

        assert_equal({"columns" => nil}, proposal.changes)
        assert_match(/hold the header row of an earlier upload/, proposal.notes.first)
      end
    end

    describe "an output category" do
      it "replaces its columns with fields, skipping the other keys" do
        proposal = proposal(RocketJob::Category::Output.new(format: :csv, columns: %w[b a]))

        assert_equal(
          {"columns" => nil, "schema" => {"fieldsMatch" => "subset", "fields" => [{"name" => "b"}, {"name" => "a"}]}},
          proposal.changes
        )
        assert(proposal.notes.any? { |note| note.start_with?("A Time is written in ISO 8601") })
      end

      it "removes the columns of a category without a format, which had no effect" do
        proposal = proposal(RocketJob::Category::Output.new(columns: %w[a]))

        assert_equal({"columns" => nil}, proposal.changes)
        assert_match(/Without a format/, proposal.notes.first)
      end

      it "replaces a fixed width layout" do
        category = RocketJob::Category::Output.new(format: :fixed, format_options: {layout: [{size: 4, key: "name"}]})

        assert_equal [{"name" => "name", "type" => "string", "width" => 4, "truncate" => true}],
                     proposal(category).schema["fields"]
      end

      it "writes what the proposed schema writes" do
        category = RocketJob::Category::Output.new(format: :csv, columns: %w[b a])
        proposed = proposal(category).proposed_category

        assert_equal category.tabular.render({"a" => 1, "b" => 2, "c" => 3}),
                     proposed.tabular.render({"a" => 1, "b" => 2, "c" => 3})
      end

      it "cannot be dry run, nor change its category" do
        assert_raises(ArgumentError) do
          proposal(RocketJob::Category::Output.new(format: :csv, columns: %w[a])).dry_run(StringIO.new("a\n"))
        end
      end
    end

    describe "a job class" do
      it "proposes the schema of each category that it defines" do
        klass = Class.new(DeprecatedJob)
        klass.defined_input_categories  = [input(format: :csv, allowed_columns: %w[a])]
        klass.defined_output_categories = [RocketJob::Category::Output.new(format: :csv, columns: %w[a])]
        klass.define_singleton_method(:name) { "ImportJob" }

        assert_equal ["ImportJob, input category main", "ImportJob, output category main"],
                     klass.schema_proposals.map(&:where)
      end

      it "does not propose again for the categories that a subclass inherits" do
        parent = Class.new(DeprecatedJob)
        parent.defined_input_categories = [input(format: :csv, allowed_columns: %w[a])]
        child = Class.new(parent)

        assert_equal 1, parent.schema_proposals.size
        assert_empty child.schema_proposals
      end
    end

    describe "#dry_run" do
      it "does not change the path that it reads, and finds text that the schema cannot read" do
        category = input(format: :csv, allowed_columns: %w[first_name zip], skip_unknown: true)
        IOStreams.temp_file("schema_proposal", ".csv") do |path|
          path.write("First Name,Zip\nJos\xE9,123\n".b)
          differences = proposal(category).dry_run(path)

          assert_nil path.setting(:encode)
          assert_equal 1, differences.size
          assert_match(/\ANow raises IOStreams::Errors::InvalidEncoding/, differences.first)
        end
      end

      it "says when the file cannot be read either way" do
        differences = proposal(input(format: :csv, allowed_columns: %w[a])).dry_run("/no/such/file.csv")

        assert_equal 1, differences.size
        assert_match(/\ARaises Errno::ENOENT, as it does now/, differences.first)
      end
    end

    describe "a saved job" do
      it "proposes for a queued job" do
        job = ProposalJob.new
        job.input_category.allowed_columns = %w[a]
        job.input_category.format          = :csv
        job.save!

        assert_equal ["SchemaProposalTest::ProposalJob #{job.id} (queued), input category main"],
                     RocketJob::Job.find(job.id).schema_proposals.map(&:where)
      end

      it "proposes nothing for the header row that its own upload read" do
        job = ProposalJob.new(state: :running, record_count: 2)
        job.input_category.format  = :csv
        job.input_category.columns = %w[first_name zip_code]

        assert_empty job.schema_proposals
      end

      it "tells a running job to finish first" do
        job = ProposalJob.new(state: :running)
        job.input_category.allowed_columns = %w[a]
        job.input_category.format          = :csv

        proposals = job.schema_proposals

        assert_equal 1, proposals.size
        assert_empty proposals.first.changes
        assert_match(/Let it finish/, proposals.first.notes.first)
      end
    end

    describe "properties" do
      let(:properties) do
        {"input_categories" => [{"name" => "main", "format" => "csv", "allowed_columns" => %w[a], "skip_unknown" => true}]}
      end

      it "of a Dirmon entry are proposed by its job class" do
        entry = RocketJob::DirmonEntry.new(name: "Imports", job_class_name: ProposalJob.name, pattern: "in/*.csv",
                                           archive_directory: "archive", properties: properties)

        proposals = entry.schema_proposals

        assert_equal ["Dirmon entry \"Imports\" #{entry.id}, input category main, in its properties"],
                     proposals.map(&:where)
        assert_equal "partial", proposals.first.schema["fieldsMatch"]
      end

      it "of an UploadFileJob are proposed by its job class" do
        job = RocketJob::Jobs::UploadFileJob.new(job_class_name: ProposalJob.name, properties: properties)

        assert_equal 1, job.schema_proposals.size
      end

      it "with the :hash mode are proposed" do
        entry = RocketJob::DirmonEntry.new(job_class_name: ProposalJob.name,
                                           properties:     {"input_categories" => [{"name" => "main", "mode" => "hash"}]})

        assert_equal [{"mode" => :line}], entry.schema_proposals.map(&:changes)
      end

      it "without a deprecated option propose nothing" do
        entry = RocketJob::DirmonEntry.new(job_class_name: ProposalJob.name,
                                           properties:     {"input_categories" => [{"name" => "main", "format" => "csv"}]})

        assert_empty entry.schema_proposals
      end
    end

    describe "an OnDemandBatchJob" do
      it "says when its code names a deprecated option" do
        job = RocketJob::Jobs::OnDemandBatchJob.new(code: "row", before_code: "upload(file, allowed_columns: %w[a])")

        assert_match(/Its before_code names a deprecated category or upload option/,
                     job.schema_proposals.last.notes.first)
      end

      it "says when its code names a deprecated mode" do
        ["upload(file, stream_mode: :line)", "input_category.mode = :hash", "upload(file, mode: :array)"].each do |code|
          job = RocketJob::Jobs::OnDemandBatchJob.new(code: "row", before_code: code)

          assert_match(/Its before_code names a deprecated/, job.schema_proposals.last&.notes&.first.to_s, code)
        end
      end

      it "does not name validate_rows or the :line mode as deprecated" do
        job = RocketJob::Jobs::OnDemandBatchJob.new(code: "row", before_code: "upload(file, validate_rows: true)\nmode: :line")

        assert_empty job.schema_proposals
      end
    end

    describe ".all" do
      it "lists a Dirmon entry whose properties cannot be read, rather than stopping" do
        RocketJob::DirmonEntry.create!(
          name:              "Bad",
          job_class_name:    ProposalJob.name,
          pattern:           "test/files/schema_proposal/*.bad",
          archive_directory: "/tmp/schema_proposal_archive",
          properties:        {"input_categories" => [{"name" => "main", "bogus" => 1, "allowed_columns" => %w[a]}]}
        )

        proposal = RocketJob::SchemaProposal.all.find { |candidate| candidate.where.start_with?("Dirmon entry \"Bad\"") }

        assert_match(/Its categories could not be read: NoMethodError/, proposal.error)
      end
    end

    describe ".report" do
      it "says when there is nothing to change" do
        assert_equal "No deprecated category options were found.", RocketJob::SchemaProposal.report([])
      end

      it "shows each proposal and what to check in the files" do
        report = RocketJob::SchemaProposal.report([proposal(input(format: :csv, allowed_columns: %w[a]))])

        assert_includes report, "ProposalJob, input category main\n  Set: allowed_columns: remove\n  Set schema: "
        assert_includes report, "For every category moved to a schema, check its files"
      end

      it "lists the saved jobs and Dirmon entries" do
        job = ProposalJob.new
        job.input_category.format       = :csv
        job.input_category.skip_unknown = true
        job.save!
        RocketJob::DirmonEntry.create!(
          name:              "Imports",
          job_class_name:    ProposalJob.name,
          pattern:           "test/files/schema_proposal/*.csv",
          archive_directory: "/tmp/schema_proposal_archive",
          properties:        {"input_categories" => [{"name" => "main", "format" => "csv", "header_cleanser" => "none"}]}
        )

        wheres = RocketJob::SchemaProposal.all.map(&:where)

        assert_includes wheres, "SchemaProposalTest::ProposalJob #{job.id} (queued), input category main"
        assert(wheres.any? { |where| where.start_with?("Dirmon entry \"Imports\"") })
      end
    end
  end
end
