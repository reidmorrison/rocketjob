module IOStreams
  class Path
    # Converts an object of this instance into a database friendly value.
    def mongoize
      to_s
    end

    # Get the object as it was stored in the database, and instantiate
    # this custom class from it.
    def self.demongoize(object)
      case object
      when String
        new(object)
      else
        object
      end
    end

    # Takes any possible object and converts it to how it would be
    # stored in the database.
    def self.mongoize(object)
      case object
      when self.class
        object.mongoize
      else
        object
      end
    end

    # Converts the object that was supplied to a criteria and converts it
    # into a database friendly form.
    def self.evolve(object)
      case object
      when self.class
        object.mongoize
      else
        object
      end
    end
  end
end
