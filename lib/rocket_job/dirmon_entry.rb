module RocketJob
  class DirmonEntry
    include MongoMapper::Document

    # Name for this path entry used to identify this DirmonEntry
    # in the user interface
    key :name,               String

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
    key :path,               String

    # Job to start
    #
    # Example:
    #   "ProcessItJob"
    key :job_name,          String

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
    key :arguments,          Array, default: []

    # Any job properties to set
    #
    # Example, override the default job priority:
    #   { priority: 45 }
    key :properties,         Hash, default: {}

    # Archive directory to move files to when processed to prevent processing the
    # file again.
    #
    # If supplied, the file will be moved to this directory before the job is started
    # If the file was in a sub-directory, the corresponding sub-directory will
    # be created in the archive directory, if the path being scanned for files
    # is a relative path. (I.e. Does not start with '/') .
    key :archive_directory,  String

    # Allow a monitoring path to be temporarily disabled
    key :enabled,            Boolean, default: true

    # Method to perform on the job, usually :perform
    key :perform_method,     Symbol, default: :perform

    # Returns the Job to be queued
    def job_class
      job_name.nil? ? nil : job_name.constantize
    end

    validates_presence_of :path, :job_name

    validates_each :job_name do |record, attr, value|
      exists = false
      begin
        exists = value.nil? ? false : value.constantize.ancestors.include?(RocketJob::Job)
      rescue NameError => exc
      end
      record.errors.add(attr, 'job_name must be defined and must be derived from RocketJob::Job') unless exists
    end

    validates_each :arguments do |record, attr, value|
      if klass = record.job_class
        count = klass.argument_count(record.perform_method)
        record.errors.add(attr, "There must be #{count} argument(s)") if  value.size != count
      end
    end

    validates_each :properties do |record, attr, value|
      if record.job_name && (methods = record.job_class.instance_methods)
        value.each_pair do |key, value|
          record.errors.add(attr, "Unknown property: #{key.inspect} with value: #{value}") unless methods.include?("#{key}=".to_sym)
        end
      end
    end

  end
end
