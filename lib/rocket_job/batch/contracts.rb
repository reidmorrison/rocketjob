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
      end

      # Returns [Class|nil] the contract that the records of the supplied input category are read through, see
      # .input_contract, which applies to the main input category only, or nil without one.
      def input_contract_for(category)
        self.class.input_contract if input_category(category).name == :main
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

        # Returns [Array<RocketJob::Category::Input|RocketJob::Category::Output>] the categories that a new job starts
        # with, see RocketJob::Batch::Categories. With a contract, a main input category without a format reads the
        # format of each file from its name, see Category::Input#detect_format, since the contract, rather than the
        # format, decides what `#perform` receives.
        def rocketjob_new_categories(key)
          categories = super
          return categories unless key == :input_categories && input_contract

          main        = categories.find { |category| category.name == :main }
          main.format = :auto if main && main.format.nil?
          categories
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
