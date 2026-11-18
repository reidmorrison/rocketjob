module IOStreams
  class Path
    # Converts an object of this instance into a database friendly value.
    def mongoize
      to_s
    end

    # Get the object as it was stored in the database, and instantiate
    # this custom class from it.
    #
    # A stored url that IOStreams cannot make a path of, such as one whose scheme IOStreams does not know, or that it
    # cannot parse, is returned as stored, a String, rather than raising, so that the name can still be read, such as
    # for its extensions, or to show it, see RocketJob.path_display_name. For example a page of a web interface, such as
    # Mission Control, that shows the job. IOStreams raises when the String is used as a path, such as with
    # IOStreams.new.
    def self.demongoize(object)
      return if object.nil?

      IOStreams.new(object)
    rescue ArgumentError, URI::Error, LoadError
      object
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
