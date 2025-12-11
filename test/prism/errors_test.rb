# frozen_string_literal: true

return if RUBY_VERSION < "3.3.0"

require_relative "test_helper"

module Prism
  class ErrorsTest < TestCase
    base = File.expand_path("errors", __dir__)
    filepaths = Dir["**/*.txt", base: base]

    filepaths.each do |filepath|
      ruby_versions_for(filepath).each do |version|
        define_method(:"test_#{version}_#{File.basename(filepath, ".txt")}") do
          assert_errors(File.join(base, filepath), version)
        end
      end
    end

    def test_newline_preceding_eof
      err = Prism.parse("foo(").errors.first
      assert_equal 1, err.location.start_line

      err = Prism.parse("foo(\n").errors.first
      assert_equal 1, err.location.start_line

      err = Prism.parse("foo(\n\n\n\n\n").errors.first
      assert_equal 5, err.location.start_line
    end

    def test_embdoc_ending
      source = <<~RUBY
        =begin\n=end
        =begin\n=end\0
        =begin\n=end\C-d
        =begin\n=end\C-z
      RUBY

      source.each_line do |line|
        assert_valid_syntax(source)
        assert_predicate Prism.parse(source), :success?
      end
    end

    def test_unterminated_string_closing
      statement = Prism.parse_statement("'hello")
      assert_equal statement.unescaped, "hello"
      assert_empty statement.closing
    end

    def test_unterminated_interpolated_string_closing
      statement = Prism.parse_statement('"hello')
      assert_equal statement.unescaped, "hello"
      assert_empty statement.closing
    end

    def test_unterminated_empty_string_closing
      statement = Prism.parse_statement('"')
      assert_empty statement.unescaped
      assert_empty statement.closing
    end

    def test_invalid_message_name
      assert_equal :"", Prism.parse_statement("+.@foo,+=foo").write_name
    end

    def test_regexp_encoding_option_mismatch_error
      # UTF-8 char with ASCII-8BIT modifier
      result = Prism.parse('/Ȃ/n')
      assert_includes result.errors.map(&:type), :regexp_encoding_option_mismatch

      # UTF-8 char with EUC-JP modifier
      result = Prism.parse('/Ȃ/e')
      assert_includes result.errors.map(&:type), :regexp_encoding_option_mismatch

      # UTF-8 char with Windows-31J modifier
      result = Prism.parse('/Ȃ/s')
      assert_includes result.errors.map(&:type), :regexp_encoding_option_mismatch

      # UTF-8 char with UTF-8 modifier
      result = Prism.parse('/Ȃ/u')
      assert_empty result.errors
    end

    private

    def assert_errors(filepath, version)
      expected = File.read(filepath, binmode: true, external_encoding: Encoding::UTF_8)

      source = expected.lines.grep_v(/^\s*\^/).join.gsub(/\n*\z/, "")
      refute_valid_syntax(source) if CURRENT_MAJOR_MINOR == version

      result = Prism.parse(source, version: version)
      errors = result.errors
      refute_empty errors, "Expected errors in #{filepath}"

      actual = result.errors_format
      assert_equal expected, actual, "Expected errors to match for #{filepath}"
    end
  end
end
