# frozen_string_literal: true

require_relative "../test_helper"
require "timeout"

module Prism
  class ParseStreamTest < TestCase
    def test_single_line
      io = StringIO.new("1 + 2")
      result = Prism.parse_stream(io)

      assert result.success?
      assert_kind_of Prism::CallNode, result.statement
    end

    def test_multi_line
      io = StringIO.new("1 + 2\n3 + 4")
      result = Prism.parse_stream(io)

      assert result.success?
      assert_kind_of Prism::CallNode, result.statement
      assert_kind_of Prism::CallNode, result.statement
    end

    def test_multi_read
      io = StringIO.new("a" * 4096 * 4)
      result = Prism.parse_stream(io)

      assert result.success?
      assert_kind_of Prism::CallNode, result.statement
    end

    def test___END__
      io = StringIO.new(<<~RUBY)
        1 + 2
        3 + 4
        __END__
        5 + 6
      RUBY
      result = Prism.parse_stream(io)

      assert result.success?
      assert_equal 2, result.value.statements.body.length
      assert_equal "5 + 6\n", io.read
    end

    # __END__ as the final line with no trailing newline must still be detected
    # as the terminator. This exercises the EOF check for a chunk that does not
    # end in a newline, distinct from a line longer than the internal read
    # buffer (which also has no trailing newline but is not the end of input).
    def test___END___without_trailing_newline
      io = StringIO.new("1 + 2\n__END__")
      result = Prism.parse_stream(io)

      assert result.success?
      assert_equal 1, result.value.statements.body.length
    end

    def test_false___END___in_string
      io = StringIO.new(<<~RUBY)
        1 + 2
        3 + 4
        "
        __END__
        "
        5 + 6
      RUBY
      result = Prism.parse_stream(io)

      assert result.success?
      assert_equal 4, result.value.statements.body.length
    end

    def test_false___END___in_regexp
      io = StringIO.new(<<~RUBY)
        1 + 2
        3 + 4
        /
        __END__
        /
        5 + 6
      RUBY
      result = Prism.parse_stream(io)

      assert result.success?
      assert_equal 4, result.value.statements.body.length
    end

    def test_false___END___in_list
      io = StringIO.new(<<~RUBY)
        1 + 2
        3 + 4
        %w[
        __END__
        ]
        5 + 6
      RUBY
      result = Prism.parse_stream(io)

      assert result.success?
      assert_equal 4, result.value.statements.body.length
    end

    def test_false___END___in_heredoc
      io = StringIO.new(<<~RUBY)
        1 + 2
        3 + 4
        <<-EOF
        __END__
        EOF
        5 + 6
      RUBY
      result = Prism.parse_stream(io)

      assert result.success?
      assert_equal 4, result.value.statements.body.length
    end

    def test_nul_bytes
      io = StringIO.new(<<~RUBY)
        1 # \0\0\0\t
        2 # \0\0\0
        3
      RUBY
      result = Prism.parse_stream(io)

      assert result.success?
      assert_equal 3, result.value.statements.body.length
    end

    # `IO#gets(limit)` will not split a multi-byte character, so it can return
    # more bytes than requested when the limit falls in the middle of one. When
    # that character straddles the internal read buffer boundary, the old code
    # wrote past the buffer and dropped the overflowing bytes, corrupting the
    # content (and overflowing the stack). Sweep offsets around the 4096-byte
    # boundary with both 3- and 4-byte characters so the straddle is hit
    # regardless of the exact internal read size.
    def test_multibyte_on_read_boundary
      ["あ", "\u{1F600}"].each do |char|
        (4080..4100).each do |prefix|
          body = ("a" * prefix) + char
          result = Prism.parse_stream(StringIO.new("\"#{body}\""))

          assert result.success?, "parse failed at prefix=#{prefix} char=#{char.dump}"
          assert_equal body, result.value.statements.body[0].content, "content mismatch at prefix=#{prefix} char=#{char.dump}"
        end
      end
    end

    # A misbehaving stream whose `gets` ignores its limit and returns an
    # arbitrarily long string must not overflow the internal buffer. The old
    # code copied the full returned length into a fixed 4096-byte buffer.
    def test_gets_exceeding_limit
      stream = Object.new
      def stream.gets(limit = nil)
        return nil if defined?(@done) && @done
        @done = true
        ("x" * 100_000) + "\n"
      end
      def stream.eof?; defined?(@done) && @done; end

      result = Prism.parse_stream(stream)
      assert result.success?
    end

    # A misbehaving stream whose `gets` returns a non-String must not be read as
    # a byte buffer. The old code called RSTRING_PTR on whatever was returned.
    def test_gets_returning_non_string
      stream = Object.new
      def stream.gets(limit = nil)
        return nil if defined?(@done) && @done
        @done = true
        1234
      end
      def stream.eof?; defined?(@done) && @done; end

      assert_nothing_raised do
        Prism.parse_stream(stream)
      end
    end

    # A misbehaving stream whose `gets` returns an empty string instead of nil
    # while never reporting EOF must not loop forever. A well-behaved stream
    # returns nil at EOF, so an empty chunk is treated as the end of input.
    def test_gets_returning_empty_string
      stream = Object.new
      def stream.gets(limit = nil); ""; end
      def stream.eof?; false; end

      result = Timeout.timeout(10) { Prism.parse_stream(stream) }
      assert result.success?
    rescue Timeout::Error
      flunk "Prism.parse_stream looped forever on a stream returning empty strings"
    end
  end
end
