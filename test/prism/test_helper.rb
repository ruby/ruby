# frozen_string_literal: true

require "prism"
require "ripper"
require "pp"
require "test/unit"
require "tempfile"

puts "Using prism backend: #{Prism::BACKEND}" if ENV["PRISM_FFI_BACKEND"]

# It is useful to have a diff even if the strings to compare are big
# However, ruby/ruby does not have a version of Test::Unit with access to
# max_diff_target_string_size
if defined?(Test::Unit::Assertions::AssertionMessage)
  Test::Unit::Assertions::AssertionMessage.max_diff_target_string_size = 5000
end

module Prism
  class TestCase < ::Test::Unit::TestCase
    private

    def assert_raises(*args, &block)
      raise "Use assert_raise instead"
    end

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
      when SourceFileNode
        expected_deconstruct = expected.deconstruct_keys(nil)
        actual_deconstruct = actual.deconstruct_keys(nil)
        assert_equal expected_deconstruct.keys, actual_deconstruct.keys

        # Filepaths can be different if test suites were run on different
        # machines. We accommodate for this by comparing the basenames, and not
        # the absolute filepaths.
        expected_filepath = expected_deconstruct.delete(:filepath)
        actual_filepath = actual_deconstruct.delete(:filepath)

        assert_equal expected_deconstruct, actual_deconstruct
        assert_equal File.basename(expected_filepath), File.basename(actual_filepath)
      when Node
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
      when Location
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
  end
end
