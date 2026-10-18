require "stringio"
require "tmpdir"

module Compat
  # One scenario: the categories of its job class and the transform of its #perform, how its job is built, the data
  # that it uploads and how, whether a worker reloads its job before processing it, and what it sets up while it runs,
  # as its definition, a Hash, supplies them. Defines its job class, builds its job, and uploads its data.
  #
  # The scenarios are defined in scenarios/, which also supply the defaults of their definitions, such as the CSV
  # file that most of them upload.
  class Scenario
    attr_reader :id, :desc

    def initialize(definition)
      @definition = definition
      @id         = definition.fetch(:id)
      @desc       = definition.fetch(:desc)
    end

    # Returns [true|false] whether a worker reloads the job from MongoDB before it is processed, rather than the
    # instance that uploaded it processing it.
    def reload?
      @definition.fetch(:reload, false)
    end

    # Returns [Class] the job class of this scenario, named after it with the supplied prefix, see JobFactory.
    def define_job(prefix)
      JobFactory.define(
        "#{prefix}#{id}",
        input:     @definition[:input],
        outputs:   @definition[:outputs],
        transform: @definition[:transform]
      )
    end

    # Returns [RocketJob::Job] a new job of the supplied class, built from the properties of this scenario, as a
    # Dirmon entry or an UploadFileJob builds it, when it has properties.
    def build(klass)
      properties = @definition[:properties]
      properties ? klass.from_properties(properties) : klass.new
    end

    # Uploads the data of this scenario into the job, from a StringIO with the file name of the data, from a file, or
    # by writing its records to the block of #upload, and returns what #upload returns.
    def upload(job)
      upload_args = @definition.fetch(:upload_args, {})
      case @definition[:via]
      when :block
        job.upload { |io| @definition.fetch(:records).each { |record| io << record } }
      when :file
        job.upload(write_file, **upload_args)
      else
        job.upload(StringIO.new(@definition.fetch(:data)), file_name: @definition.fetch(:file_name), **upload_args)
      end
    end

    # Runs the block while the setup of this scenario is in place, such as `IOStreams.enforce_column_restrictions =
    # false`, which its definition supplies as a lambda that returns the lambda that undoes it.
    def around
      undo = @definition[:setup]&.call
      yield
    ensure
      undo&.call
    end

    # Returns [Hash] the definition of this scenario, to show in its result.
    def to_h
      {
        "input"       => @definition[:input]&.inspect,
        "outputs"     => @definition[:outputs].inspect,
        "properties"  => @definition[:properties]&.inspect,
        "file_name"   => @definition[:file_name],
        "via"         => (@definition[:via] || :stringio).to_s,
        "upload_args" => @definition.fetch(:upload_args, {}).inspect,
        "data"        => @definition[:via] == :block ? @definition[:records].inspect : @definition[:data],
        "setup"       => @definition[:setup_desc]
      }.compact
    end

    private

    def write_file
      path = File.join(Dir.mktmpdir("compat"), @definition.fetch(:file_name))
      File.write(path, @definition.fetch(:data))
      path
    end
  end
end
