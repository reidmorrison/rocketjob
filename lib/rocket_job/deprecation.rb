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
    UPGRADE_GUIDE = "https://rocketjob.reidmorrison.com/upgrading.html#upgrading-to-v71".freeze

    # Reports that the application used something deprecated, unless deprecation warnings are off, with the message,
    # which says what is deprecated and what to use instead, after "Rocket Job: ", at the first line of the call stack
    # outside this library and the libraries that call it, or without a line when there is none, such as in a worker
    # that builds the job of a Dirmon entry.
    #
    # Returns nil.
    def self.warn(message)
      return unless enabled?

      dirs    = library_dirs
      uplevel = caller_locations(1).index { |location| !library?(location, dirs) }
      # Kernel#warn counts its own caller, this method, as level 0.
      Kernel.warn("Rocket Job: #{message}", uplevel: uplevel && (uplevel + 1), category: :deprecated)
      nil
    end

    # Returns [true|false] whether deprecation warnings are on, see Warning[:deprecated], and so whether .warn reports
    # them. A check that costs something to find a use of what is deprecated, such as one that compares every record
    # of an upload, runs only while they are, so that production, where they are off, does not pay for it.
    def self.enabled?
      Warning[:deprecated]
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
