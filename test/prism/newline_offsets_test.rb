# frozen_string_literal: true

require_relative "test_helper"

module Prism
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
      assert_newline_offsets_for("\"\\C-\r\n\"", "\\C- with \\r\\n")
    end

    private

    def assert_newline_offsets(fixture)
      assert_newline_offsets_for(fixture.read)
    end

    def assert_newline_offsets_for(source, message = nil)
      expected = [0]
      source.b.scan("\n") { expected << $~.offset(0)[0] + 1 }

      assert_equal expected, Prism.parse(source).source.offsets, message
    end
  end
end
