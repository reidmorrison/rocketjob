module Compat
  # Returns views of a batch job that JSON holds and that compare exactly: its categories, why it is not valid, its
  # state with the errors of its failed slices, the records in its input slices, and its categories as they are
  # stored in MongoDB.
  module Inspection
    # The fields of a category that the scenarios set or that an upload changes.
    CATEGORY_FIELDS = %w[name format format_options schema columns allowed_columns required_columns skip_unknown
                         header_cleanser mode file_name nils].freeze

    # Returns [Hash] the input and output categories of the job.
    def self.categories(job)
      {
        "input"  => job.input_categories.map { |category| category(category) },
        "output" => job.output_categories.map { |category| category(category) }
      }
    end

    # Returns [Hash] the fields of the category, see CATEGORY_FIELDS.
    def self.category(category)
      fields = category.attributes.slice(*CATEGORY_FIELDS).transform_values do |value|
        value.is_a?(IOStreams::Path) ? value.to_s : value
      end
      JSON.parse(JSON.generate(fields))
    rescue StandardError => e
      {"error" => "#{e.class}: #{e.message}"}
    end

    # Returns [Hash] why the job, and each of its categories, is not valid.
    def self.validation_errors(job)
      job.valid?
      {
        "job"    => job.errors.full_messages,
        "input"  => job.input_categories.map { |category| category.valid? ? [] : category.errors.full_messages },
        "output" => job.output_categories.map { |category| category.valid? ? [] : category.errors.full_messages }
      }
    rescue StandardError => e
      {"error" => "#{e.class}: #{e.message}"}
    end

    # Returns [Hash] the state of the job, and the error of each slice that failed.
    def self.state(job)
      failed = job.input.failed.to_a
      {
        "state"         => job.state.to_s,
        "sub_state"     => job.sub_state.to_s,
        "failed_slices" => failed.size,
        "slice_errors"  => failed.map { |slice| slice.exception && "#{slice.exception.class_name}: #{slice.exception.message}" },
        "exception"     => job.exception && "#{job.exception.class_name}: #{job.exception.message}"
      }
    rescue StandardError => e
      {"error" => "#{e.class}: #{e.message}"}
    end

    # Returns [Array<String>] the records in the input slices of the category, as they were uploaded.
    def self.uploaded_records(job, category = :main)
      job.input(category).collect(&:to_a).flatten(1).map { |record| Result.show(record) }
    rescue StandardError => e
      ["(could not read the input slices: #{e.class}: #{e.message})"]
    end

    # Returns [Hash] the categories of the job with the supplied id, as they are stored in MongoDB.
    def self.stored_categories(id)
      document = RocketJob::Job.collection.find(_id: BSON::ObjectId.from_string(id.to_s)).first
      return {"error" => "not found"} unless document

      %w[input_categories output_categories].to_h do |key|
        [key, Array(document[key]).map { |category| JSON.parse(category.except("_id").to_json) }]
      end
    end
  end
end
