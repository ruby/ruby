# frozen_string_literal: true

require_relative "../test_helper"

module Ruby::Prism
  class RaiseErrorTest < TestCase
    def test_option_not_set
      assert_nothing_raised { Ruby::Prism.parse("foo = 1 +") }
      assert_nothing_raised { Ruby::Prism.parse("foo = 1 +", raise_error: nil) }
    end

    def test_option_invalid
      error = assert_raise(ArgumentError) { Ruby::Prism.parse("foo = 1", raise_error: :bogus) }
      assert_includes error.message, "invalid raise_error value: bogus"

      error = assert_raise(TypeError) { Ruby::Prism.parse("foo = 1", raise_error: "plain") }
      assert_equal "wrong argument type String (expected Symbol)", error.message
    end

    def test_option_misspelled
      error = assert_raise(ArgumentError) { Ruby::Prism.parse("foo = 1 +", raise_errors: :plain) }
      assert_includes error.message, "unknown keyword"
    end

    def test_syntax_error_single
      error = assert_raise(SyntaxError) { Ruby::Prism.parse("foo(\n", raise_error: :plain, filepath: "single.rb") }
      assert_includes error.message, "syntax error found"
      assert_syntax_error_path "single.rb", error
    end

    def test_syntax_error_multiple
      error = assert_raise(SyntaxError) { Ruby::Prism.parse("foo = 1 +\n", raise_error: :plain, filepath: "test.rb") }
      assert_includes error.message, "syntax errors found"
    end

    def test_syntax_error_true
      # The formatting is determined by whether or not $stderr is a terminal
      # and the NO_COLOR environment variable, so only assert that it raises.
      assert_raise(SyntaxError) { Ruby::Prism.parse("foo = 1 +\n", raise_error: true) }
    end

    def test_syntax_error_style
      error = assert_raise(SyntaxError) { Ruby::Prism.parse("foo = 1 +\n", raise_error: :style) }
      assert_include error.message, "\e[m"
      assert_not_include error.message, "\e[1;31m"
    end

    def test_syntax_error_color
      error = assert_raise(SyntaxError) { Ruby::Prism.parse("foo = 1 +\n", raise_error: :color) }
      assert_include error.message, "\e[1;31m"
    end

    def test_syntax_error_many_on_one_line
      # Every comma is its own error. Errors on a line are displayed in windows
      # of bounded width, so the message grows linearly with the input.
      source = "," * 4096
      error = assert_raise(SyntaxError) { Ruby::Prism.parse(source, raise_error: :plain) }
      assert_operator error.message.bytesize, :<, source.bytesize * 200
    end

    def test_syntax_error_far_apart_on_one_line
      # The errors at either end of the line are displayed in separate windows,
      # so the whitespace between them is not repeated beneath the line.
      source = "x#{" " * 100_000},,"
      error = assert_raise(SyntaxError) { Ruby::Prism.parse(source, raise_error: :plain) }
      assert_operator error.message.bytesize, :<, source.bytesize
      assert_equal 2, error.message.scan("> 1 |").size
    end

    def test_syntax_error_wide_line_numbers
      # The gutter is as wide as the widest line number displayed, so the
      # markers beneath the line stay aligned with the source.
      error = assert_raise(SyntaxError) { Ruby::Prism.parse("1 2", raise_error: :plain, line: 123_456) }
      source_line, marker_line = error.message.lines.grep(/\|/).first(2)

      assert_equal "> 123456 | 1 2\n", source_line
      assert_equal source_line.index("|"), marker_line.index("|")
      assert_equal source_line.rindex("2"), marker_line.index("^")
    end

    def test_syntax_error_context_line_numbers
      # The gutter is as wide as the widest line number displayed, including the
      # lines of context after the last error.
      source = "x = 1\n" * 98 + "1 2\n" + "y = 2\n" * 2
      error = assert_raise(SyntaxError) { Ruby::Prism.parse(source, raise_error: :plain) }
      gutters = error.message.lines.grep(/\|/).map { |line| line.index("|") }

      assert_includes error.message, "101 | y = 2"
      assert_equal [gutters.first], gutters.uniq
    end

    def test_syntax_error_not_utf8_in_context
      # A line of context is displayed, so it must be valid UTF-8 for the
      # snippet to be displayed, even though it has no error of its own.
      source = "# caf\xE9\n1 2\n".b.force_encoding(Encoding::UTF_8)
      error = assert_raise(SyntaxError) { Ruby::Prism.parse(source, raise_error: :plain) }

      assert_predicate error.message, :valid_encoding?
      assert_not_include error.message, "> 2 |"
    end

    def test_syntax_error_long_context_line
      # Lines of context are cut off at the width of a window.
      source = "x = #{"a" * 100_000}\n1 2\n"
      error = assert_raise(SyntaxError) { Ruby::Prism.parse(source, raise_error: :plain) }

      assert_operator error.message.bytesize, :<, 1000
      assert_match(/^  1 \| x = a+ \.\.\.$/, error.message)
    end

    def test_syntax_error_not_utf8
      error = assert_raise(SyntaxError) { Ruby::Prism.parse("foo = 1 + \xFF\xFE\n".b, raise_error: :plain, filepath: "bin.rb") }
      assert_include error.message, "invalid multibyte character"
      assert_not_include error.message, "> 1 |"
    end

    def test_argument_error
      assert_raise(ArgumentError) { Ruby::Prism.parse("# encoding: bogus\n1 + 1\n", raise_error: :plain, filepath: "enc.rb") }
    end

    def test_load_error
      error = assert_raise(LoadError) { Ruby::Prism.parse("foo = 1\n", raise_error: :plain, command_line: "x") }
      assert_nil error.path
    end

    def test_string_apis
      source = "foo = 1 +\n"
      apis = [
        -> { Ruby::Prism.parse(source, raise_error: :plain) },
        -> { Ruby::Prism.lex(source, raise_error: :plain) },
        -> { Ruby::Prism.parse_lex(source, raise_error: :plain) },
        -> { Ruby::Prism.parse_comments(source, raise_error: :plain) },
        -> { Ruby::Prism.profile(source, raise_error: :plain) },
        -> { Ruby::Prism.parse_success?(source, raise_error: :plain) },
        -> { Ruby::Prism.parse_failure?(source, raise_error: :plain) },
        -> { Ruby::Prism.parse_stream(StringIO.new(source), raise_error: :plain) }
      ]

      if !ENV["PRISM_BUILD_MINIMAL"]
        apis << -> { Ruby::Prism.dump(source, raise_error: :plain) }
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
          -> { Ruby::Prism.parse_file(filepath, raise_error: :plain) },
          -> { Ruby::Prism.lex_file(filepath, raise_error: :plain) },
          -> { Ruby::Prism.parse_lex_file(filepath, raise_error: :plain) },
          -> { Ruby::Prism.parse_file_comments(filepath, raise_error: :plain) },
          -> { Ruby::Prism.profile_file(filepath, raise_error: :plain) },
          -> { Ruby::Prism.parse_file_success?(filepath, raise_error: :plain) },
          -> { Ruby::Prism.parse_file_failure?(filepath, raise_error: :plain) }
        ]

        if !ENV["PRISM_BUILD_MINIMAL"]
          apis << -> { Ruby::Prism.dump_file(filepath, raise_error: :plain) }
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
          Ruby::Prism.parse(source, raise_error: :plain)
          Ruby::Prism.lex(source, raise_error: :plain)
          Ruby::Prism.parse_lex(source, raise_error: :plain)
          Ruby::Prism.parse_comments(source, raise_error: :plain)
          Ruby::Prism.profile(source, raise_error: :plain)
          Ruby::Prism.parse_success?(source, raise_error: :plain)
          Ruby::Prism.parse_stream(StringIO.new(source), raise_error: :plain)
          Ruby::Prism.parse_file(file.path, raise_error: :plain)

          if !ENV["PRISM_BUILD_MINIMAL"]
            Ruby::Prism.dump(source, raise_error: :plain)
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
