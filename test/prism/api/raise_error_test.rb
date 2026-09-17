# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class RaiseErrorTest < TestCase
    def test_option_not_set
      assert_nothing_raised { Prism.parse("foo = 1 +") }
      assert_nothing_raised { Prism.parse("foo = 1 +", raise_error: nil) }
    end

    def test_option_invalid
      error = assert_raise(ArgumentError) { Prism.parse("foo = 1", raise_error: :bogus) }
      assert_includes error.message, "invalid raise_error value: bogus"

      error = assert_raise(TypeError) { Prism.parse("foo = 1", raise_error: "plain") }
      assert_equal "wrong argument type String (expected Symbol)", error.message
    end

    def test_option_misspelled
      error = assert_raise(ArgumentError) { Prism.parse("foo = 1 +", raise_errors: :plain) }
      assert_includes error.message, "unknown keyword"
    end

    def test_syntax_error_single
      error = assert_raise(SyntaxError) { Prism.parse("foo(\n", raise_error: :plain, filepath: "single.rb") }
      assert_includes error.message, "syntax error found"
      assert_syntax_error_path "single.rb", error
    end

    def test_syntax_error_multiple
      error = assert_raise(SyntaxError) { Prism.parse("foo = 1 +\n", raise_error: :plain, filepath: "test.rb") }
      assert_includes error.message, "syntax errors found"
    end

    def test_syntax_error_true
      # The formatting is determined by whether or not $stderr is a terminal
      # and the NO_COLOR environment variable, so only assert that it raises.
      assert_raise(SyntaxError) { Prism.parse("foo = 1 +\n", raise_error: true) }
    end

    def test_syntax_error_style
      error = assert_raise(SyntaxError) { Prism.parse("foo = 1 +\n", raise_error: :style) }
      assert_include error.message, "\e[m"
      assert_not_include error.message, "\e[1;31m"
    end

    def test_syntax_error_color
      error = assert_raise(SyntaxError) { Prism.parse("foo = 1 +\n", raise_error: :color) }
      assert_include error.message, "\e[1;31m"
    end

    def test_syntax_error_not_utf8
      error = assert_raise(SyntaxError) { Prism.parse("foo = 1 + \xFF\xFE\n".b, raise_error: :plain, filepath: "bin.rb") }
      assert_include error.message, "invalid multibyte character"
      assert_not_include error.message, "> 1 |"
    end

    def test_argument_error
      assert_raise(ArgumentError) { Prism.parse("# encoding: bogus\n1 + 1\n", raise_error: :plain, filepath: "enc.rb") }
    end

    def test_load_error
      error = assert_raise(LoadError) { Prism.parse("foo = 1\n", raise_error: :plain, command_line: "x") }
      assert_nil error.path
    end

    def test_string_apis
      source = "foo = 1 +\n"
      apis = [
        -> { Prism.parse(source, raise_error: :plain) },
        -> { Prism.lex(source, raise_error: :plain) },
        -> { Prism.parse_lex(source, raise_error: :plain) },
        -> { Prism.parse_comments(source, raise_error: :plain) },
        -> { Prism.profile(source, raise_error: :plain) },
        -> { Prism.parse_success?(source, raise_error: :plain) },
        -> { Prism.parse_failure?(source, raise_error: :plain) },
        -> { Prism.parse_stream(StringIO.new(source), raise_error: :plain) }
      ]

      if !ENV["PRISM_BUILD_MINIMAL"]
        apis << -> { Prism.dump(source, raise_error: :plain) }
      end

      apis.each do |api|
        error = assert_raise(SyntaxError, &api)
        assert_syntax_error_path "", error
      end
    end

    def test_file_apis
      Tempfile.create(["raise_error", ".rb"]) do |file|
        file.write("foo = 1 +\n")
        file.close

        filepath = file.path
        apis = [
          -> { Prism.parse_file(filepath, raise_error: :plain) },
          -> { Prism.lex_file(filepath, raise_error: :plain) },
          -> { Prism.parse_lex_file(filepath, raise_error: :plain) },
          -> { Prism.parse_file_comments(filepath, raise_error: :plain) },
          -> { Prism.profile_file(filepath, raise_error: :plain) },
          -> { Prism.parse_file_success?(filepath, raise_error: :plain) },
          -> { Prism.parse_file_failure?(filepath, raise_error: :plain) }
        ]

        if !ENV["PRISM_BUILD_MINIMAL"]
          apis << -> { Prism.dump_file(filepath, raise_error: :plain) }
        end

        apis.each do |api|
          error = assert_raise(SyntaxError, &api)
          assert_syntax_error_path filepath, error
        end
      end
    end

    def test_valid_source
      source = "foo = 1\n"

      Tempfile.create(["raise_error", ".rb"]) do |file|
        file.write(source)
        file.close

        assert_nothing_raised do
          Prism.parse(source, raise_error: :plain)
          Prism.lex(source, raise_error: :plain)
          Prism.parse_lex(source, raise_error: :plain)
          Prism.parse_comments(source, raise_error: :plain)
          Prism.profile(source, raise_error: :plain)
          Prism.parse_success?(source, raise_error: :plain)
          Prism.parse_stream(StringIO.new(source), raise_error: :plain)
          Prism.parse_file(file.path, raise_error: :plain)

          if !ENV["PRISM_BUILD_MINIMAL"]
            Prism.dump(source, raise_error: :plain)
          end
        end
      end
    end

    private

    if RUBY_ENGINE == "truffleruby"
      def assert_syntax_error_path(expected, error)
      end
    elsif SyntaxError.method_defined?(:path)
      def assert_syntax_error_path(expected, error)
        assert_equal expected, error.path
      end
    else
      def assert_syntax_error_path(expected, error)
        assert_equal expected, error.instance_variable_get(:@path)
      end
    end
  end
end
