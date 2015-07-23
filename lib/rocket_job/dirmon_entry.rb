module RocketJob
  class DirmonEntry
    include MongoMapper::Document

    # Name for this path entry used to identify this DirmonEntry
    # in the user interface and is passed into the job when kicked off
    key :name,         String

    # Wildcard path to search for files in
    #
    # Example:
    #   input_files/process1/*.csv*
    #   input_files/process2/**/*
    #
    # For details on valid path values, see: http://ruby-doc.org/core-2.2.2/Dir.html#method-c-glob
    #
    # Note
    # - If there are no '*' in the path then an exact filename match is expected
    key :path,          String

    # Job to start
    #
    # Example:
    #   "ProcessItJob"
    key :job,           String

    # Any user supplied arguments for the method invocation
    # All keys must be UTF-8 strings. The values can be any valid BSON type:
    #   Integer
    #   Float
    #   Time    (UTC)
    #   String  (UTF-8)
    #   Array
    #   Hash
    #   True
    #   False
    #   Symbol
    #   nil
    #   Regular Expression
    #
    # Note: Date is not supported, convert it to a UTC time
    key :arguments,     Array, default: []

    # Any job properties to set
    #
    # Example, override the default job priority:
    #   { priority: 45 }
    key :properties,    Hash, default: {}

    # Archive directory to move files to when processed to prevent processing the
    # file again.
    #
    # If supplied, the file will be moved to this directory before the job is started
    # If the file was in a sub-directory, the corresponding sub-directory will
    # be created in the archive directory, if the path being scanned for files
    # is a relative path. (I.e. Does not start with '/') .
    key :archive_directory,  String

    # Allow a monitoring path to be temporarily disabled
    key :enabled,       Boolean, default: true

    validates_presence_of :path, :job
  end
end
