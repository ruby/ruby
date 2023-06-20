# frozen_string_literal: true

require "yarp"
require "ripper"
require "pp"
require "test/unit"
require "tempfile"

module YARP
  module Assertions
    private

    def assert_equal_nodes(expected, actual, compare_location: true, parent: nil)
      assert_equal expected.class, actual.class

      case expected
      when Array
        assert_equal(
          expected.size,
          actual.size,
          -> { "Arrays were different sizes. Parent: #{parent.pretty_inspect}" }
        )

        expected.zip(actual).each do |(expected_element, actual_element)|
          assert_equal_nodes(
            expected_element,
            actual_element,
            compare_location: compare_location,
            parent: actual
          )
        end
      when YARP::SourceFileNode
        deconstructed_expected = expected.deconstruct_keys(nil)
        deconstructed_actual = actual.deconstruct_keys(nil)
        assert_equal deconstructed_expected.keys, deconstructed_actual.keys

        # Filepaths can be different if test suites were run
        # on different machines.
        # We accommodate for this by comparing the basenames,
        # and not the absolute filepaths
        assert_equal deconstructed_expected.except(:filepath), deconstructed_actual.except(:filepath)
        assert_equal File.basename(deconstructed_expected[:filepath]), File.basename(deconstructed_actual[:filepath])
      when YARP::Node
        deconstructed_expected = expected.deconstruct_keys(nil)
        deconstructed_actual = actual.deconstruct_keys(nil)
        assert_equal deconstructed_expected.keys, deconstructed_actual.keys

        deconstructed_expected.each_key do |key|
          assert_equal_nodes(
            deconstructed_expected[key],
            deconstructed_actual[key],
            compare_location: compare_location,
            parent: actual
          )
        end
      when YARP::Location
        assert_operator actual.start_offset, :<=, actual.end_offset, -> {
          "start_offset > end_offset for #{actual.inspect}, parent is #{parent.pretty_inspect}"
        }
        if compare_location
          assert_equal(
            expected.start_offset,
            actual.start_offset,
            -> { "Start locations were different. Parent: #{parent.pretty_inspect}" }
          )

          assert_equal(
            expected.end_offset,
            actual.end_offset,
            -> { "End locations were different. Parent: #{parent.pretty_inspect}" }
          )

        end
      else
        assert_equal expected, actual
      end
    end

    def assert_valid_locations(value, parent: nil)
      case value
      when Array
        value.each do |element|
          assert_valid_locations(element, parent: value)
        end
      when YARP::Node
        value.deconstruct_keys(nil).each_value do |field|
          assert_valid_locations(field, parent: value)
        end
      when YARP::Location
        assert_operator value.start_offset, :<=, value.end_offset, -> {
          "start_offset > end_offset for #{value.inspect}, parent is #{parent.pretty_inspect}"
        }
      end
    end
  end
end

Test::Unit::TestCase.include(YARP::Assertions)
