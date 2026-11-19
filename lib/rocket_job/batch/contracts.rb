require "active_support/concern"

module RocketJob
  module Batch
    # The contract of a batch job: the fields that `#perform` needs, and the type of each one, see IOStreams::Contract.
    # The job class owns it, since it is code that changes with `#perform`, and it is never saved with the job. The
    # input category keeps what describes the file instead, such as its format and schema, see Category::Input.
    #
    # Each record of the main input category is read through the contract, whatever its source: a file in any format,
    # a query, a range or the records of `upload_slice`, so that `#perform` receives a record of the contract, such as
    # `order.amount`, rather than a Hash keyed by the columns of one file.
    #
    # Example:
    #   class ImportOrdersJob < RocketJob::Job
    #     include RocketJob::Batch
    #
    #     input_contract do
    #       fields_match "partial"
    #
    #       field :id,     :integer, required: true
    #       field :amount, :number,  decimals: 2
    #     end
    #
    #     def perform(order)
    #       Ledger.post(order.id, order.amount)
    #     end
    #   end
    module Contracts
      extend ActiveSupport::Concern

      included do
        class_attribute :rocketjob_input_contract, instance_accessor: false, instance_predicate: false

        validate :rocketjob_input_contract_schema, if: :rocketjob_check_input_contract_schema?
      end

      # Returns [Class|nil] the contract that the records of the supplied input category are read through, see
      # .input_contract, which applies to the main input category only, or nil without one.
      def input_contract_for(category)
        self.class.input_contract if input_category(category).name == :main
      end

      private

      # Adds an error when the schema of the main input category would not meet the input contract, see
      # Category::Input#schema_contract_errors.
      def rocketjob_input_contract_schema
        input_category.schema_contract_errors(self.class.input_contract).each do |error|
          errors.add(:input_categories, "main: #{error.message}")
        end
      end

      # Returns [true|false] whether to check the schema of the main input category against the input contract: for a
      # new job, or one whose input categories changed, so that a job that a worker saves as it runs is not checked
      # against a contract that a later deploy changed.
      def rocketjob_check_input_contract_schema?
        return false unless self.class.input_contract

        new_record? || input_categories.any? { |category| category.new_record? || category.changed? }
      end

      module ClassMethods
        # Declares the contract of the main input category, or returns the one declared, or nil without one.
        #
        # Parameters:
        #   contract [Class]
        #     A subclass of IOStreams::Contract, to share one contract between jobs, or with the web request that
        #     accepts an upload.
        #   block
        #     The fields of the contract, as the body of a subclass of IOStreams::Contract, see IOStreams::Contract.field,
        #     which builds the class `InputContract` within this job class, such as `ImportOrdersJob::InputContract`.
        #
        # A subclass of this job starts with its contract, and declaring one replaces it for the subclass only.
        #
        # Raises ArgumentError for both a contract and a block, or a contract that is not a subclass of
        # IOStreams::Contract.
        def input_contract(contract = nil, &block)
          return rocketjob_input_contract unless contract || block
          raise(ArgumentError, "Supply either a contract class or a block to input_contract, not both") if contract && block

          contract = rocketjob_contract_class(:InputContract, &block) if block
          unless contract.is_a?(Class) && contract < IOStreams::Contract
            raise(ArgumentError, "input_contract needs a subclass of IOStreams::Contract, not #{contract.inspect}")
          end

          self.rocketjob_input_contract = contract
        end

        # Returns [Array<Exception>] every reason that the supplied file cannot be uploaded into the main input category
        # through the input contract, each an exception that is not raised, such as an IOStreams::Errors::InvalidHeader
        # for each field that the contract requires and the file does not have, or an IOStreams::Errors::IncompatibleType
        # for a column whose declared type never fits, or [] when it can, or when this job class has no contract. It
        # reads only the start of the file, see Category::Input#contract_errors, so that a web request that accepts a
        # file can report every problem before any job is created. An upload raises for the columns of a file before
        # its first slice, see Category::Input#copy_slices, but not for a file without a header row, such as an empty
        # one, which uploads no records. Empty for a job class without a main input category.
        #
        # Parameters:
        #   path [String|IOStreams::Path]
        #     The file to check.
        #   properties [Hash]
        #     The properties that the job would be built from, see .from_properties, such as those of a Dirmon entry,
        #     whose main input category, such as its format or schema, describes the file. The job is not built.
        #   original_file_name [String]
        #     The name that the file was uploaded with, whose extension gives its format and streams, when the path has
        #     another name, such as once a Dirmon entry archived it.
        def input_contract_errors(path, properties = nil, original_file_name: nil)
          return [] unless input_contract

          category = rocketjob_input_category_from(properties)
          return [] unless category

          category.contract_errors(path, input_contract, original_file_name: original_file_name)
        end

        # Returns [Array<String>] why the supplied properties cannot build this job, see
        # RocketJob::Batch::Categories.property_errors, also when the schema of the main input category that they give
        # it would not meet the input contract, see Category::Input#schema_contract_errors, so that a Dirmon entry whose
        # files no upload could read is not saved.
        def property_errors(properties)
          errors = super
          return errors unless errors.empty? && input_contract

          rocketjob_input_category_from(properties).schema_contract_errors(input_contract).map do |error|
            "Input category main: #{error.message}"
          end
        end

        # Returns [Array<RocketJob::Category::Input|RocketJob::Category::Output>] the categories that a new job starts
        # with, see RocketJob::Batch::Categories. With a contract, the main input category reads the format of each file
        # from its name, see Category::Input#detect_format, since the contract, rather than the format, decides what
        # `#perform` receives, unless this job class declares the format of the main input category, see
        # .input_format_declared?, which it keeps, also when it is nil.
        def rocketjob_new_categories(key)
          categories = super
          return categories unless key == :input_categories && input_contract
          return categories if input_format_declared?(:main)

          categories.each { |category| category.format = :auto if category.name == :main && category.format.nil? }
        end

        private

        # Returns [Class] a subclass of IOStreams::Contract built from the supplied block, named the supplied constant
        # within this job class, which replaces one of the same name that this class, not its parent, declared.
        def rocketjob_contract_class(name, &)
          contract = Class.new(IOStreams::Contract, &)
          send(:remove_const, name) if const_defined?(name, false)
          const_set(name, contract)
        end
      end
    end
  end
end
