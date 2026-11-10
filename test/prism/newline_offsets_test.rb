# frozen_string_literal: true

require_relative "test_helper"

module Ruby::Prism
  class NewlineOffsetsTest < TestCase
    Fixture.each do |fixture|
      define_method(fixture.test_name) { assert_newline_offsets(fixture) }
    end

    def test_escape_control_newline
      # Newlines consumed inside escape sequences like \C-, \c, and \M-
      # must be tracked in line offsets across all literal types.
      %w[\\C- \\c \\M-].each do |escape|
        assert_newline_offsets_for("\"#{escape}\n\"", "#{escape} in string")
        assert_newline_offsets_for("`#{escape}\n`", "#{escape} in xstring")
        assert_newline_offsets_for("/#{escape}\n/", "#{escape} in regexp")
        assert_newline_offsets_for("%Q{#{escape}\n}", "#{escape} in %Q")
        assert_newline_offsets_for("%W[#{escape}\n]", "#{escape} in %W")
        assert_newline_offsets_for("<<~H\n#{escape}\n\nH\n", "#{escape} in heredoc")
        assert_newline_offsets_for("?#{escape}\n", "#{escape} in char literal")
      end

      # Combined meta + control escapes
      assert_newline_offsets_for("\"\\M-\\C-\n\"", "\\M-\\C- in string")
      assert_newline_offsets_for("\"\\M-\\c\n\"", "\\M-\\c in string")

      # \r\n consumed inside escape context
      %w[\\C- \\c \\M- \\M-\\C-].each do |escape|
        assert_newline_offsets_for("\"#{escape}\r\n\"", "#{escape} with \\r\\n in string")
        assert_newline_offsets_for("/#{escape}\r\n/", "#{escape} with \\r\\n in regexp")
        assert_newline_offsets_for("%W[#{escape}\r\n]", "#{escape} with \\r\\n in %W")
        assert_newline_offsets_for("<<H\r\n#{escape}\r\n\r\nH\r\n", "#{escape} with \\r\\n in heredoc")
        assert_newline_offsets_for("?#{escape}\r\n", "#{escape} with \\r\\n in char literal")
      end
    end

    def test_newline_delimiter_with_pending_heredoc
      # A newline delimiter closing a literal on a line whose heredoc body has
      # been lexed resumes after that body, so each line is recorded once.
      %w[%W %I %r %Q %].each do |literal|
        assert_newline_offsets_for("#{literal}\n\#{<<A}\nb\nA\n", literal)
        assert_newline_offsets_for("#{literal}\r\n\#{<<A}\r\nb\r\nA\r\n", "#{literal} with \\r\\n")
      end
    end

    def test_escaped_newline_with_pending_heredoc
      # An escape consuming the newline of a line whose heredoc body has been
      # lexed resumes after that body, so each line is recorded exactly once.
      ["\\\n", "\\c\n", "\\C-\n", "\\M-\n", "\\M-\\C-\n", "\\C-\\\r\n"].each do |escape|
        assert_newline_offsets_for("\"\#{<<A}#{escape}b\nA\nc\"\n", "#{escape.inspect} in string")
        assert_newline_offsets_for("`\#{<<A}#{escape}b\nA\nc`\n", "#{escape.inspect} in xstring")
        assert_newline_offsets_for("/\#{<<A}#{escape}b\nA\nc/\n", "#{escape.inspect} in regexp")
        assert_newline_offsets_for("%Q{\#{<<A}#{escape}b\nA\nc}\n", "#{escape.inspect} in %Q")
        assert_newline_offsets_for("%W[\#{<<A}#{escape}b\nA\nc]\n", "#{escape.inspect} in %W")
        assert_newline_offsets_for("<<B\n\#{<<A}#{escape}b\nA\nc\nB\n", "#{escape.inspect} in heredoc")
        assert_newline_offsets_for("<<~B\n\#{<<A}#{escape}b\nA\nc\nB\n", "#{escape.inspect} in dedenting heredoc")
        assert_newline_offsets_for("[<<A, ?#{escape}b\nA\n]\n", "#{escape.inspect} in char literal")
      end
    end

    private

    def assert_newline_offsets(fixture)
      assert_newline_offsets_for(fixture.read)
    end

    def assert_newline_offsets_for(source, message = nil)
      expected = [0]
      source.b.scan("\n") { expected << $~.offset(0)[0] + 1 }

      assert_equal expected, Ruby::Prism.parse(source).source.offsets, message
    end
  end
end
