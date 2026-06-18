# frozen_string_literal: true
require_relative 'test_helper'

class JSONMinefieldParserTest < Test::Unit::TestCase
  # Test fixtures from https://github.com/nst/JSONTestSuite
  # https://seriot.ch/security/parsing_json.html

  fixtures = Dir[File.join(File.expand_path("../fixtures/minefield", __FILE__), "*.json")]

  class << self
    private

    def define_test(name, &block)
      if RUBY_ENGINE == 'jruby' && JRUBY_PENDING.include?(name)
        define_method("test_#{name}") do
          pend("#{name} doesn't pass on JRuby", &block)
        end
      else
        define_method("test_#{name}", &block)
      end
    end
  end

  JRUBY_PENDING = %w(
    n_structure_open_array_object
    n_structure_100000_opening_arrays
    n_object_trailing_comment_slash_open
  ).freeze

  INVALID_ENCODING_TESTS = %w(
    i_string_truncated-utf-8
    i_string_overlong_sequence_6_bytes_null
    i_string_overlong_sequence_6_bytes
    i_string_overlong_sequence_2_bytes
    i_string_not_in_unicode_range
    i_string_lone_utf8_continuation_byte
    i_string_lone_second_surrogate
    i_string_iso_latin_1
    i_string_invalid_utf-8
    i_string_incomplete_surrogate_pair
    i_string_UTF-8_invalid_sequence
    i_object_key_lone_2nd_surrogate
  )

  COMMENT_TESTS = %w(
    n_object_trailing_comment
    n_object_trailing_comment_slash_open
    n_structure_object_with_comment
  ).freeze

  DUPLICATE_KEY_TESTS = %w(
    y_object_duplicated_key
    y_object_duplicated_key_and_value
  ).freeze

  # Tests starting with `i_` aren't defined by the spec, we can chose to
  # change our behavior, but ideally we'd be consistent across the Java and C
  # parsers.
  UNDEFINED_FAILING = %w(
    i_string_1st_surrogate_but_2nd_missing
    i_string_1st_valid_surrogate_2nd_invalid
    i_string_UTF-16LE_with_BOM
    i_string_incomplete_surrogate_and_escape_valid
    i_string_incomplete_surrogates_escape_valid
    i_string_invalid_lonely_surrogate
    i_string_invalid_surrogate
    i_string_inverted_surrogates_U+1D11E
    i_string_utf16BE_no_BOM
    i_string_utf16LE_no_BOM
    i_structure_UTF-8_BOM_empty_object
  )

  if RUBY_ENGINE == 'jruby'
    # The Java parser validate the document encoding
    # but the C parser doesn't.
    # See: https://github.com/ruby/json/issues/138
    UNDEFINED_FAILING.concat(INVALID_ENCODING_TESTS)
  end

  fixtures.each do |path|
    payload = File.read(path)
    name = File.basename(path, '.json')

    if COMMENT_TESTS.include?(name)
      define_test(name) do
        JSON.parse(payload, allow_comments: true)

        assert_raise(JSON::ParserError) do
          JSON.parse(payload, allow_comments: false)
        end
      end
    elsif DUPLICATE_KEY_TESTS.include?(name)
      define_test(name) do
        JSON.parse(payload, allow_duplicate_key: true)
        assert_raise(JSON::ParserError) do
          JSON.parse(payload, allow_duplicate_key: false)
        end
      end
    elsif name.start_with?("y_") || (name.start_with?("i_") && !UNDEFINED_FAILING.include?(name))
      define_test(name) do
        JSON.parse(payload, max_nesting: false, allow_duplicate_key: false, allow_comments: false)
        assert true
      end
    elsif name.start_with?("n_") || (name.start_with?("i_") && UNDEFINED_FAILING.include?(name))
      define_test(name) do
        assert_raise(JSON::ParserError) do
          JSON.parse(payload, max_nesting: false, allow_comments: true)
        end
      end
    else
      raise "Unexpected minefield test: #{name}"
    end
  end
end