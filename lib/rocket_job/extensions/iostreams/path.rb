module IOStreams
  class Path
    # Converts an object of this instance into a database friendly value.
    def mongoize
      to_s
    end

    # Get the object as it was stored in the database, and instantiate
    # this custom class from it.
    #
    # A stored url that IOStreams cannot make a path of is returned as stored, a String, rather than raising, so that
    # the name can still be read, such as for its extensions, or to show it, see RocketJob.path_display_name. Such as:
    # - a url that IOStreams cannot parse, such as an SFTP url with a non-ASCII letter in its file name. For example
    #   the `file_name` of a category, which an UploadFileJob that Dirmon created in Rocket Job 7.1 set from the
    #   unencoded url of an SFTP file, see RocketJob::DirmonEntry#file_display_name.
    # - a url whose scheme needs a gem that this process does not load, such as an S3 url in a web process without
    #   aws-sdk-s3, while the workers that read the file load it.
    # - a url whose scheme IOStreams does not know, such as one that the application registers in another process.
    # IOStreams raises when the String is used as a path, such as with IOStreams.new.
    def self.demongoize(object)
      return if object.nil?

      IOStreams.new(object)
    rescue ArgumentError, URI::Error, LoadError
      object
    end

    # Returns [true|false] whether IOStreams cannot make a path of the supplied url in this process, other than for a
    # gem that this process does not load, since a server that runs the job can load it: such as a url whose scheme
    # IOStreams does not know, or that it cannot parse, which .demongoize keeps as stored.
    def self.invalid_url?(url)
      IOStreams.path(url)
      false
    rescue ArgumentError, URI::Error
      true
    rescue LoadError
      false
    end

    # Takes any possible object and converts it to how it would be
    # stored in the database.
    def self.mongoize(object)
      return if object.nil?

      object.to_s
    end

    # Converts the object that was supplied to a criteria and converts it
    # into a database friendly form.
    def self.evolve(object)
      return if object.nil?

      object.to_s
    end
  end
end
