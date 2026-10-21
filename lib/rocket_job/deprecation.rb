module RocketJob
  # Reports the use of a deprecated option or method as a Ruby deprecation warning, see `Kernel#warn`, as IOStreams
  # does, see `IOStreams::Deprecation`:
  # - Only while deprecation warnings are on, see `Warning[:deprecated]`. They are off by default, so production stays
  #   quiet, and on in tests run by Minitest or test-unit, or with `ruby -W:deprecated` or `RUBYOPT=-W:deprecated`.
  # - Written to `$stderr`, unless the application routes them elsewhere, such as to its log, or raises them in its
  #   tests, by overriding `Warning.warn`.
  #
  # Each warning names the first line of the call stack outside Rocket Job, such as the line of a job class that
  # defines a category with a deprecated option, rather than a line of Rocket Job.
  module Deprecation
    # The directory of the files of this library, whose lines are skipped when finding the line that used it.
    LIB_DIR = "#{File.expand_path('..', __dir__)}/".freeze

    # Where the upgrade guide says what replaces each deprecated option.
    UPGRADE_GUIDE = "https://rocketjob.reidmorrison.com/upgrading.html".freeze

    # The states of a job that can still run, and so read its saved options, see .saved_options.
    RUNNABLE_JOB_STATES = %w[queued running paused failed].freeze

    # Returns [Array<String>] a line for each saved job, Dirmon entry and UploadFileJob that holds a deprecated
    # option, such as an input category's `allowed_columns`, which no warning reports, since reading a saved document
    # does not warn, so that they can be changed before upgrading to a release that removes the option. Each document
    # decides which of its options are deprecated, see RocketJob::Plugins::Job::Model#deprecated_options and
    # RocketJob::DirmonEntry#deprecated_options.
    #
    # Only the jobs that can still run are read: queued, which includes scheduled, running, paused and failed. Each
    # document is read on its own, so that one that cannot be read is listed, and the others still are: a job whose
    # class cannot be loaded in this process, a Dirmon entry or an UploadFileJob whose job class cannot be, since their
    # options cannot be read, and a document that raises when it is read, with its error.
    #
    # Example:
    #   puts RocketJob::Deprecation.saved_options
    #   # ImportJob 6512f1c0a1b2c3d4e5f60718 (queued): input category main: allowed_columns, skip_unknown
    #   # Dirmon entry "Daily orders" 6512f1c0a1b2c3d4e5f60719: input category main: mode
    def self.saved_options
      jobs = RocketJob::Job.where(:state.in => RUNNABLE_JOB_STATES).pluck(:id).flat_map do |id|
        saved_document_options(RocketJob::Job, "Job", id) { |job| "#{job.class.name} #{job.id} (#{job.state})" }
      end
      entries = RocketJob::DirmonEntry.pluck(:id).flat_map do |id|
        saved_document_options(RocketJob::DirmonEntry, "Dirmon entry", id) do |entry|
          "Dirmon entry #{entry.name.inspect} #{entry.id}"
        end
      end
      jobs + entries
    end

    # Returns [Array<String>] the lines of .saved_options for the saved document of the supplied class and id, which
    # the block names once it is read, or the supplied kind and the id when it cannot be read. None when it was removed
    # since its id was read.
    def self.saved_document_options(klass, kind, id)
      document = klass.where(id: id).first
      return [] if document.nil?

      label   = yield(document)
      options = document.deprecated_options
      return ["#{label}: the class of the job that it creates cannot be loaded, so its options cannot be read"] if options.nil?

      options.map { |where, names| "#{label}: #{where}: #{names.join(', ')}" }
    rescue StandardError => e
      return ["#{kind} #{id}: its class cannot be loaded, so its options cannot be read"] if unloadable_class?(e)

      ["#{kind} #{id}: cannot be read: #{e.class.name}: #{e.message}"]
    end
    private_class_method :saved_document_options

    # Returns [true|false] whether the supplied error, which reading a saved document raised, says that its class cannot
    # be loaded: Mongoid knows of no such class, or loading it named a constant that is not defined, rather than a
    # NoMethodError, which is a NameError too, raised by the code of a class that was loaded, such as a callback.
    def self.unloadable_class?(error)
      error.is_a?(Mongoid::Errors::UnknownModel) || (error.is_a?(NameError) && !error.is_a?(NoMethodError))
    end
    private_class_method :unloadable_class?

    # Reports that the application used something deprecated, unless deprecation warnings are off, with the message,
    # which says what is deprecated and what to use instead, after "Rocket Job: ", at the first line of the call stack
    # outside this library and the libraries that call it, or without a line when there is none, such as in a worker
    # that builds the job of a Dirmon entry.
    #
    # Returns nil.
    def self.warn(message)
      return unless Warning[:deprecated]

      dirs    = library_dirs
      uplevel = caller_locations(1).index { |location| !library?(location, dirs) }
      # Kernel#warn counts its own caller, this method, as level 0.
      Kernel.warn("Rocket Job: #{message}", uplevel: uplevel && (uplevel + 1), category: :deprecated)
      nil
    end

    # Returns [Array<String>] the directories whose lines are skipped when finding the line of the application: this
    # library, the other gems, which call it back, such as Active Support's callbacks and Mongoid, and Ruby's own
    # library.
    def self.library_dirs
      gems = Gem.loaded_specs.each_value.filter_map { |spec| "#{spec.full_gem_path}/" unless spec.name == "rocketjob" }
      [LIB_DIR, "#{RbConfig::CONFIG['rubylibdir']}/", *gems]
    end
    private_class_method :library_dirs

    # Returns [true|false] whether the line of the call stack is in a file of a library, see .library_dirs, or of Ruby
    # itself.
    def self.library?(location, dirs)
      path = (location.absolute_path || location.path).to_s
      path.start_with?("<internal:") || dirs.any? { |dir| path.start_with?(dir) }
    end
    private_class_method :library?
  end
end
