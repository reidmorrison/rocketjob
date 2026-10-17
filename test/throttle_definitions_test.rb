require_relative "test_helper"

class ThrottleDefinitionsTest < Minitest::Test
  describe RocketJob::ThrottleDefinitions do
    let(:definitions) do
      definitions = RocketJob::ThrottleDefinitions.new
      definitions.add(:first_exceeded?, :throttle_filter_class)
      definitions
    end

    describe "#with" do
      it "returns a copy with the throttle added after the others" do
        copy = definitions.with(:second_exceeded?, :throttle_filter_id, "Second")

        assert_equal %i[first_exceeded? second_exceeded?], copy.throttles.collect(&:method_name)
        assert_equal "Second", copy.throttles.last.description
      end

      it "does not change the throttles that it is called on" do
        definitions.with(:second_exceeded?, :throttle_filter_id)

        assert_equal %i[first_exceeded?], definitions.throttles.collect(&:method_name)
      end

      it "rejects a throttle that is already defined" do
        assert_raises(ArgumentError) { definitions.with(:first_exceeded?, :throttle_filter_class) }
      end
    end

    describe "#without" do
      it "returns a copy without the throttle" do
        assert_empty definitions.without(:first_exceeded?).throttles
      end

      it "does not change the throttles that it is called on" do
        definitions.without(:first_exceeded?)

        assert definitions.exist?(:first_exceeded?)
      end
    end

    describe "#remove" do
      it "does not change a copy made with dup" do
        copy = definitions.dup
        copy.remove(:first_exceeded?)

        assert definitions.exist?(:first_exceeded?)
        refute copy.exist?(:first_exceeded?)
      end
    end
  end
end
