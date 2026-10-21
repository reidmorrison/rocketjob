module RocketJob
  # The schema proposed to replace the deprecated options of one category, see RocketJob::Category::Base#schema, of a
  # job class, a saved job, a Dirmon entry or an UploadFileJob, so that each can be moved to a schema before Rocket Job
  # 8 removes those options. A category proposes its own, see RocketJob::Category::Input#schema_proposal, from what
  # its options did in Rocket Job 7.0, which is not always what they say.
  #
  # A proposal changes nothing: review it, read a recent file with it, see #dry_run, and apply it by hand, since a
  # schema reads some files differently from the options that it replaces.
  #
  # Example, from a console of the application, once its job classes are loaded:
  #   puts RocketJob::SchemaProposal.report
  class SchemaProposal
    # What to check in the files of any category moved to a schema, since a schema reads them differently.
    FILE_CHECKS = [
      "A row with more values than the columns of its file raises IOStreams::Errors::InvalidHeader. Before, the " \
      "values after the last column were ignored.",
      "Two columns that cleanse to one name raise IOStreams::Errors::InvalidHeader. Before, the last one won.",
      "Text that is not valid UTF-8 raises IOStreams::Errors::InvalidEncoding, unless an encoding is set on the " \
      "path that is uploaded. Before, every character that was not ASCII was removed.",
      "A column whose name only loosely matches a field, such as firstname for first_name, is read. Before, it was " \
      "dropped.",
      "The keys of each record are in the order of the fields. Before, they were in the order of the file."
    ].freeze

    # The states of a saved job that can still run, and so read its categories.
    RUNNABLE_JOB_STATES = %w[queued running paused failed].freeze

    # Returns [String] where the category is, such as "ImportJob, input category main".
    attr_reader :where

    # Returns [RocketJob::Category::Input|RocketJob::Category::Output] the category that the proposal is for, as it is.
    attr_reader :category

    # Returns [Hash] the settings that replace the deprecated options, by name, such as
    # `{"allowed_columns" => nil, "schema" => {...}}`: a deprecated option is set to its default, and the schema to the
    # one proposed. Empty when the category needs no change of its own, such as a job that is already running.
    attr_reader :changes

    # Returns [Array<String>] what to check before applying the proposal, or why there is none.
    attr_reader :notes

    # Returns [String|nil] why the deprecated options could not be translated into a schema, which then needs to be
    # written by hand, or nil when they could.
    attr_reader :error

    def initialize(where:, category: nil, changes: {}, notes: [], error: nil)
      @where    = where
      @category = category
      @changes  = changes
      @notes    = notes
      @error    = error
    end

    # Returns [Array<RocketJob::SchemaProposal>] the proposals for every batch job class that is loaded, see
    # RocketJob::Batch::Categories::ClassMethods#schema_proposals, every saved job that can still run, see
    # RocketJob::Plugins::Job::Model#schema_proposals, and every Dirmon entry, see
    # RocketJob::DirmonEntry#schema_proposals. In an application that loads its classes lazily, such as Rails in
    # development, load them first, for example with `Rails.application.eager_load!`.
    def self.all
      proposals = []
      RocketJob::Job.descendants.sort_by(&:to_s).each do |klass|
        next unless klass.name && klass.respond_to?(:schema_proposals)

        proposals.concat(owned_by(klass.name) { klass.schema_proposals })
      end
      RocketJob::Job.where(:state.in => RUNNABLE_JOB_STATES).pluck(:id).each do |id|
        job = saved_job(id)
        next if job.nil?

        unless job
          proposals << new(where: "Job #{id}", notes: ["Its class cannot be loaded, so its categories cannot be read."])
          next
        end
        proposals.concat(owned_by("#{job.class.name} #{id}") { job.schema_proposals })
      end
      RocketJob::DirmonEntry.each do |entry|
        proposals.concat(owned_by("Dirmon entry #{entry.name.inspect} #{entry.id}") { entry.schema_proposals })
      end
      proposals
    end

    # Returns [Array<RocketJob::SchemaProposal>] the proposals of one owner, which the block returns, or one that says
    # why its categories could not be read, such as a category property that its job class does not have, so that one
    # of them does not stop the others from being listed.
    def self.owned_by(where)
      yield
    rescue StandardError => e
      [new(where: where, error: "Its categories could not be read: #{e.class}: #{e.message}")]
    end
    private_class_method :owned_by

    # Returns [String] the proposals, see .all, and what to check in the files of every category moved to a schema, to
    # print, or "No deprecated category options were found." when there are none.
    def self.report(proposals = all)
      return "No deprecated category options were found." if proposals.empty?

      checks = FILE_CHECKS.map { |check| "  - #{check}" }
      [*proposals.map(&:to_s), "For every category moved to a schema, check its files, see #dry_run:", *checks].join("\n\n")
    end

    # Returns [RocketJob::Job] the saved job with the supplied id, nil when it was removed since it was found, or false
    # when its class cannot be loaded in this process.
    def self.saved_job(id)
      RocketJob::Job.where(id: id).first
    rescue NameError, Mongoid::Errors::MongoidError
      false
    end
    private_class_method :saved_job

    # Returns [Hash] the schema proposed, or nil when the deprecated options are removed without one, such as column
    # options that never applied to JSON records.
    def schema
      changes["schema"]
    end

    # Returns [String] the proposal to show to people: where it is, the settings that replace the deprecated options, and
    # what to check before applying them.
    def to_s
      lines = [where]
      lines << "  Cannot translate: #{error}" if error
      unless changes.empty?
        removed = changes.except("schema").map { |name, value| value.nil? ? "#{name}: remove" : "#{name}: #{value.inspect}" }
        lines << "  Set: #{removed.join(', ')}" unless removed.empty?
        lines << "  Set schema: #{schema.inspect}" if schema
      end
      notes.each { |note| lines << "  Check: #{note}" }
      lines.join("\n")
    end

    # Returns [Array<String>] how the first records of the supplied file differ when they are read with this
    # proposal, from how its category reads them now, see RocketJob::Category::Input#preview, such as a key that is
    # missing, or a value or error that changed. Empty when they are the same. Changes nothing.
    #
    # The file is read twice, so supply its file name or IOStreams path, or a stream that responds to #rewind.
    #
    # Raises ArgumentError for a proposal that is not for an input category, or that has no changes.
    def dry_run(stream, limit: 100)
      unless category.is_a?(RocketJob::Category::Input) && changes.any?
        raise(ArgumentError, "Only the proposal for an input category can read a file")
      end

      before = read(category, stream, limit)
      after  = read(proposed_category, stream, limit)
      compare(before, after)
    end

    # Returns [RocketJob::Category::Input|RocketJob::Category::Output] a copy of the category with the proposed
    # changes, see #changes.
    def proposed_category
      copy = category.deep_dup
      changes.except("schema").each_pair { |name, value| copy.public_send(:"#{name}=", value) }
      copy.schema = schema if schema
      copy
    end

    private

    # Returns [Array|Exception] the records of the file read by the category, or what reading it raised.
    def read(category, stream, limit)
      # A stream, such as a StringIO, is read from its start each time.
      stream.rewind if stream.respond_to?(:rewind)
      category.preview(stream, limit: limit)
    rescue StandardError => e
      e
    end

    def compare(before, after)
      # Hashes are equal whatever the order of their keys, which a record's keys keep.
      return [] if in_order(before) == in_order(after)
      if before.is_a?(Exception) && after.instance_of?(before.class) && after.message == before.message
        return ["Raises #{after.class}, as it does now: #{after.message}"]
      end
      return ["Now raises #{after.class}: #{after.message}"] if after.is_a?(Exception) && !before.is_a?(Exception)
      return ["No longer raises #{before.class}: #{before.message}"] if before.is_a?(Exception) && !after.is_a?(Exception)
      return ["Raises #{after.class} rather than #{before.class}: #{after.message}"] if before.is_a?(Exception)

      differences = []
      differences << "Reads #{after.size} records rather than #{before.size}" if before.size != after.size
      before.zip(after).each_with_index do |(old, new), index|
        difference = compare_record(old, new)
        differences << "Record #{index + 1}: #{difference}" if difference
      end
      differences
    end

    def in_order(records)
      return records unless records.is_a?(Array)

      records.map { |record| record.is_a?(Hash) ? record.to_a : record }
    end

    def compare_record(old, new)
      return "#{new.inspect} rather than #{old.inspect}" unless old.is_a?(Hash) && new.is_a?(Hash)
      return if old == new && old.keys == new.keys
      return "keys in another order: #{new.keys.inspect} rather than #{old.keys.inspect}" if old == new

      compare_keys(old, new).join("; ")
    end

    def compare_keys(old, new)
      parts   = []
      missing = old.keys - new.keys
      added   = new.keys - old.keys
      parts << "keys no longer read: #{missing.inspect}" unless missing.empty?
      parts << "new keys: #{added.inspect}" unless added.empty?
      (old.keys & new.keys).each do |key|
        parts << "#{key.inspect} is #{new[key].inspect} rather than #{old[key].inspect}" if old[key] != new[key]
      end
      parts
    end
  end
end
