# Job to dynamically perform ruby code on demand as a Batch,
#
# Often used for data correction or cleansing.
#
# Example: Iterate over all rows in a table:
#   code = <<-CODE
#     if user = User.find(row)
#       user.cleanse_attributes!
#       user.save(validate: false)
#     end
#   CODE
#   job  = RocketJob::Jobs::OnDemandBatchJob.new(code: code, description: 'cleanse users')
#   arel = User.unscoped.all.order('updated_at DESC')
#   job.upload(arel)
#   job.save!
#
# Console Testing:
#   code = <<-CODE
#     if user = User.find(row)
#       user.cleanse_attributes!
#       user.save(validate: false)
#     end
#   CODE
#   job  = RocketJob::Jobs::OnDemandBatchJob.new(code: code, description: 'cleanse users')
#
#   # Run against a sub-set using a limit
#   arel = User.unscoped.all.order('updated_at DESC').limit(100)
#   job.upload(arel)
#
#   # Run the subset directly within the console
#   job.perform_now
#   job.cleanup!
#
# By default output is not collected, call the method `#collect_output` to collect output.
#
# Example:
#   job = RocketJob::Jobs::OnDemandBatchJob(
#     description:              'Fix data',
#     code:                     code,
#     throttle_running_workers: 5,
#     priority:                 30
#   )
#   job.collect_output
#   job.save!
#
# Example: Move the upload operation into a before_batch.
#   upload_code = <<-CODE
#     arel = User.unscoped.all.order('updated_at DESC')
#     upload(arel)
#   CODE
#
#   code = <<-CODE
#     if user = User.find(row)
#       user.cleanse_attributes!
#       user.save(validate: false)
#     end
#   CODE
#
#   RocketJob::Jobs::OnDemandBatchJob.create!(
#     upload_code: upload_code,
#     code:        code,
#     description: 'cleanse users'
#   )
module RocketJob
  module Jobs
    class OnDemandBatchJob < RocketJob::Job
      include RocketJob::Plugins::Cron
      include RocketJob::Plugins::Retry
      include RocketJob::Batch
      include RocketJob::Batch::Statistics

      self.priority            = 90
      self.description         = "On Demand Batch Job"
      self.destroy_on_complete = false
      self.retry_limit         = 0

      # Code that is performed against every row / record.
      field :code, type: String, user_editable: true, copy_on_restart: true

      # Optional code to execute before the batch is run.
      # Usually to upload data into the job.
      field :before_code, type: String, user_editable: true, copy_on_restart: true

      # Optional code to execute after the batch is run.
      # Usually to upload data into the job.
      field :after_code, type: String, user_editable: true, copy_on_restart: true

      # Data that is made available to the job during the perform.
      # Be sure to store key names only as Strings, not Symbols.
      field :data, type: Hash, default: {}, user_editable: true, copy_on_restart: true

      validates :code, presence: true
      validate :validate_code
      validate :validate_before_code
      validate :validate_after_code

      before_slice :load_perform_code
      before_batch :run_before_code
      after_batch :run_after_code

      # Shortcut for setting the slice_size
      def slice_size=(slice_size)
        input_category.slice_size = slice_size
      end

      # Add a new output category and collect output for it.
      def add_output_category(**args)
        output_categories << RocketJob::Category::Output.new(**args)
      end

      # Matches the code of a job that names a deprecated option, see #schema_proposals, other than an option of upload,
      # see #rocketjob_upload_option_names:
      # - the name of a deprecated category option, see RocketJob::Category::Base.deprecated_option_names, such as
      #   `input_category.allowed_columns = %w[a]`,
      # - a deprecated mode, see RocketJob::Category::Input::DEPRECATED_MODES, set as a Symbol or a String, with a Symbol
      #   or a String key, such as `mode: :hash`, `mode = "array"`, or `"mode" => "hash"`. A space can only come before
      #   `=` or `=>`, so that a ternary, such as `csv ? mode : :hash`, is not matched.
      DEPRECATED_CODE = begin
        category_options = RocketJob::Category::Input.deprecated_option_names |
                           RocketJob::Category::Output.deprecated_option_names
        /\b(#{category_options.join('|')})\b|
         \bmode["']?(:|\s*=>?)\s*[:"'](#{RocketJob::Category::Input::DEPRECATED_MODES.join('|')})\b/x
      end
      private_constant :DEPRECATED_CODE

      # Returns [Array<RocketJob::SchemaProposal>] the schemas proposed for this job's categories, see
      # RocketJob::Batch::Categories#schema_proposals, and a note when its code names a deprecated option, which a
      # proposal cannot translate: a category option or mode, see DEPRECATED_CODE, or an option that it passes to
      # upload, see RocketJob::Batch::IO.deprecated_upload_options.
      def schema_proposals
        proposals      = super
        upload_options = RocketJob::Batch::IO.deprecated_upload_options.map(&:to_s)
        names          = %w[code before_code after_code].select do |name|
          source = name == "code" ? perform_source : public_send(name).to_s
          source.match?(DEPRECATED_CODE) || rocketjob_upload_option_names(source).intersect?(upload_options)
        end
        return proposals if names.empty?

        proposals << RocketJob::SchemaProposal.new(
          where: "#{self.class.name} #{id} (#{state})",
          notes: ["Its #{names.join(', ')} #{names.size == 1 ? 'names' : 'name'} a deprecated category or upload " \
                  "option, which needs to be changed by hand."]
        )
      end

      private

      def load_perform_code
        instance_eval(perform_source, __FILE__, __LINE__)
      end

      # Returns [String] the source of #perform, which runs `code`.
      def perform_source
        "def perform(row)\n#{code}\nend"
      end

      # Returns [Array<String>] the names of the options that the supplied source passes by name in its calls to
      # upload, such as `on_first` for `upload(file, on_first: ...)` or `job.upload file, "delimiter" => "|"`, read with
      # Ruby's own parser, see Ripper. So a variable with the name of an option is not one, nor is an option of another
      # method, such as `IOStreams.path(file_name).each(:line, delimiter: "|")` in the block of upload. Options that
      # the call does not name, such as `upload(file, **options)` or `send(:upload, file, delimiter: "|")`, are not
      # read. None for source that does not parse.
      #
      # The parse tree is walked with a stack of its own, rather than by recursion, so that deeply nested code, such as
      # a long chain of calls, cannot overflow the stack of the thread.
      def rocketjob_upload_option_names(source)
        require "ripper"

        names = []
        nodes = [Ripper.sexp(source)].grep(Array)
        until nodes.empty?
          node = nodes.pop
          names.concat(rocketjob_option_names(rocketjob_upload_arguments(node)))
          nodes.concat(node.grep(Array))
        end
        names
      end

      # Returns the node of the arguments of the supplied node of the parse tree when it is a call to upload, with or
      # without parentheses or a receiver, such as `upload(file)`, `upload file` or `job.upload(file)`, otherwise nil.
      def rocketjob_upload_arguments(node)
        case node.first
        when :method_add_arg
          method = node[1].first == :fcall ? node[1][1] : node[1][3] if %i[fcall call].include?(node[1].first)
          node[2][1] if rocketjob_upload?(method) && node[2].first == :arg_paren
        when :command
          node[2] if rocketjob_upload?(node[1])
        when :command_call
          node[4] if rocketjob_upload?(node[3])
        end
      end

      def rocketjob_upload?(identifier)
        identifier.is_a?(Array) && identifier[0] == :@ident && identifier[1] == "upload"
      end

      # Returns [Array<String>] the names of the keys of the Hash, with or without braces, among the supplied
      # arguments of a call, but not of a call within them.
      def rocketjob_option_names(arguments)
        return [] unless arguments.is_a?(Array)

        case arguments.first
        when :bare_assoc_hash
          arguments[1].filter_map { |assoc| rocketjob_key_name(assoc[1]) if assoc.first == :assoc_new }
        when :hash
          rocketjob_option_names([:bare_assoc_hash, arguments.dig(1, 1) || []])
        when :args_add_block, :args_add_star, Array
          arguments.flat_map { |argument| rocketjob_option_names(argument) }
        else
          []
        end
      end

      # Returns [String] the name of the supplied key of a Hash, such as `on_first:`, `:on_first`, `"on_first" =>` or
      # `"on_first":`, or nil for a key that is not a literal name.
      def rocketjob_key_name(key)
        case key.first
        when :@label
          key[1].delete_suffix(":")
        when :symbol_literal
          key.dig(1, 1, 1)
        when :string_literal, :dyna_symbol
          content = key[1]
          content[1][1] if content.size == 2 && content[1].is_a?(Array) && content[1].first == :@tstring_content
        end
      end

      def run_before_code
        instance_eval(before_code) if before_code
      end

      def run_after_code
        instance_eval(after_code) if after_code
      end

      def validate_code
        return if code.nil?

        validate_field(:code) { load_perform_code }
      end

      def validate_before_code
        return if before_code.nil?

        validate_field(:before_code) { instance_eval("def __before_code\n#{before_code}\nend", __FILE__, __LINE__) }
      end

      def validate_after_code
        return if after_code.nil?

        validate_field(:after_code) { instance_eval("def __after_code\n#{after_code}\nend", __FILE__, __LINE__) }
      end

      def validate_field(field)
        yield
      rescue Exception => e
        errors.add(field, "Failed to load :#{field}, #{e.inspect}")
      end

      # Allow multiple instances of this job to run with the same cron schedule
      def rocket_job_cron_singleton_check
      end
    end
  end
end
