require "semantic_logger"

module Compat
  # Records what Rocket Job and IOStreams report while the scenarios run, under the scenario that was running: each
  # warning, such as a deprecation warning, with the file and line that it names and whose code that line is in, and
  # each warning or error that they log.
  module Capture
    # The longest part of a logged message or payload that is kept.
    LIMIT = 400

    @warnings = []
    @logs     = []
    @scenario = "load"

    class << self
      attr_reader :warnings, :logs, :scenario

      # Turns deprecation warnings on, as Minitest does, and records every warning instead of writing it to $stderr.
      def install
        Warning[:deprecated] = true
        Warning.singleton_class.prepend(Warnings)
      end

      # Runs the block as the supplied scenario, so that what is reported meanwhile is recorded under it.
      def during(scenario)
        previous  = @scenario
        @scenario = scenario
        yield
      ensure
        @scenario = previous
      end

      # Records a warning. Kernel#warn(uplevel:) puts the file and line that it names in front of its message.
      def warning(message, category)
        text           = message.to_s.chomp
        location, body = text.match(/\A(.+?:\d+): warning: (.*)\z/m)&.captures
        @warnings << {
          "scenario" => scenario,
          "category" => category&.to_s,
          "location" => location,
          "where"    => origin(location),
          "message"  => body || text
        }
        nil
      end

      # Records a log entry of SemanticLogger.
      def log(log)
        @logs << {
          "scenario"  => scenario,
          "level"     => log.level.to_s,
          "name"      => log.name,
          "message"   => log.message.to_s[0, LIMIT],
          "payload"   => log.payload&.inspect&.slice(0, LIMIT),
          "exception" => log.exception && "#{log.exception.class}: #{log.exception.message.to_s[0, LIMIT]}"
        }
      end

      # Returns [String] whose code the supplied file and line is in: the harness, which stands in for the
      # application, Rocket Job, IOStreams, or another library.
      def origin(location)
        return "none" if location.nil?
        return "application (harness)" if location.start_with?(Paths::DIR)

        library = libraries.find { |_name, dir| location.start_with?(dir) }
        library ? library.first : "other"
      end

      # Returns [String] the supplied file and line, relative to the harness or to the library that it is in.
      def short(location)
        return location if location.nil?
        return location.sub(Paths::DIR, "compat") if location.start_with?(Paths::DIR)

        name, dir = libraries.find { |_name, path| location.start_with?(path) }
        name ? location.sub(dir, "#{name}/lib") : location
      end

      private

      # Returns [Hash<String, String>] the lib directory of Rocket Job and of IOStreams, as this process loaded them.
      def libraries
        @libraries ||= %w[rocketjob iostreams].filter_map do |name|
          spec = Gem.loaded_specs[name]
          [name, File.join(spec.full_gem_path, "lib")] if spec
        end
      end
    end

    # Records each warning, see Capture.warning, in place of Warning.warn.
    module Warnings
      def warn(message, category: nil, **)
        Capture.warning(message, category)
      end
    end

    # Records each entry that is logged, see Capture.log.
    class Logs < SemanticLogger::Subscriber
      def log(log)
        Capture.log(log)
        true
      end
    end
  end
end
