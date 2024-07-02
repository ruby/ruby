# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class ErrorsTest < TestCase
    base = File.expand_path("errors", __dir__)
    filepaths = Dir["*.txt", base: base]

    if RUBY_VERSION < "3.0"
      filepaths -= [
        "cannot_assign_to_a_reserved_numbered_parameter.txt",
        "writing_numbered_parameter.txt",
        "targeting_numbered_parameter.txt",
        "defining_numbered_parameter.txt",
        "defining_numbered_parameter_2.txt",
        "numbered_parameters_in_block_arguments.txt"
      ]
    end

    filepaths.each do |filepath|
      define_method(:"test_#{File.basename(filepath, ".txt")}") do
        assert_errors(File.join(base, filepath))
      end
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

    def test_circular_parameters
      source = <<~RUBY
        def foo(bar = bar) = 42
        def foo(bar: bar) = 42
        proc { |foo = foo| }
        proc { |foo: foo| }
      RUBY

      source.each_line do |line|
        assert_predicate Prism.parse(line, version: "3.3.0"), :failure?
        assert_predicate Prism.parse(line), :success?
      end
    end

    private

    def assert_errors(filepath)
      expected = File.read(filepath)

      source = expected.lines.grep_v(/^\s*\^/).join.gsub(/\n*\z/, "")
      refute_valid_syntax(source)

      result = Prism.parse(source)
      errors = result.errors
      refute_empty errors, "Expected errors in #{filepath}"

      actual = result.errors_format
      assert_equal expected, actual, "Expected errors to match for #{filepath}"
    end
  end
end
