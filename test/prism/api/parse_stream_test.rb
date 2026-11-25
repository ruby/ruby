# frozen_string_literal: true

require_relative "../test_helper"
require "timeout"

module Ruby::Prism
  class ParseStreamTest < TestCase
    def test_single_line
      io = StringIO.new("1 + 2")
      result = Ruby::Prism.parse_stream(io)

      assert result.success?
      assert_kind_of Ruby::Prism::CallNode, result.statement
    end

    def test_multi_line
      io = StringIO.new("1 + 2\n3 + 4")
      result = Ruby::Prism.parse_stream(io)

      assert result.success?
      assert_kind_of Ruby::Prism::CallNode, result.statement
      assert_kind_of Ruby::Prism::CallNode, result.statement
    end

    def test_multi_read
      io = StringIO.new("a" * 4096 * 4)
      result = Ruby::Prism.parse_stream(io)

      assert result.success?
      assert_kind_of Ruby::Prism::CallNode, result.statement
    end

    def test___END__
      io = StringIO.new(<<~RUBY)
        1 + 2
        3 + 4
        __END__
        5 + 6
      RUBY
      result = Ruby::Prism.parse_stream(io)

      assert result.success?
      assert_equal 2, result.value.statements.body.length
      assert_equal "5 + 6\n", io.read
    end

    def test___END___after_syntax_error
      io = StringIO.new(")\n__END__\ndata\n")
      result = Ruby::Prism.parse_stream(io)

      assert_predicate result, :failure?
      assert_equal "__END__\n", result.data_loc.slice
      assert_equal "data\n", io.read
    end

    def test_eof_diagnostic_before___END__
      ["\n", "\r\n"].each do |newline|
        code = "[#{newline}"
        marker = "__END__#{newline}"
        io = StringIO.new(code + marker + "data\n")
        buffer = Ruby::Prism.parse(io.string)
        stream = Ruby::Prism.parse_stream(io)

        [buffer, stream].each do |result|
          assert_equal [:array_term], result.errors.map(&:type)
          assert_equal code.bytesize - 1, result.errors.first.location.start_offset
          assert_equal "\n", result.errors.first.location.slice
        end

        assert_equal marker + "data\n", buffer.data_loc.slice
        assert_equal marker, stream.data_loc.slice
        assert_equal "data\n", io.read
      end
    end

    def test___END___in_an_unterminated_interpolation
      code = '"#{value' + "\n"
      source = code + "__END__\ndata\n"

      [Ruby::Prism.parse(source), Ruby::Prism.parse_stream(StringIO.new(source))].each do |result|
        assert_equal code, result.statement.slice
        assert_equal [:unexpected_token_close_context, :embexpr_end, :string_interpolated_term], result.errors.map(&:type)
        assert_equal code.bytesize, result.errors.first.location.start_offset
      end
    end

    def test_continued_heredoc_resumes_at___END__
      code = "<<~OUTER\n" + '#{<<INNER}' + "\\c\n" + '#{value' + "\n"
      source = code + "__END__\ndata\n"

      [Ruby::Prism.parse(source), Ruby::Prism.parse_stream(StringIO.new(source))].each do |result|
        assert_equal [:heredoc_term, :embexpr_end, :heredoc_term], result.errors.map(&:type)
        part = result.statement.parts.last
        assert_equal "\n", part.unescaped
        assert_equal code.bytesize, part.location.end_offset
      end
    end

    def test___END___before_ruby_shebang
      [["preamble", { command_line: "x" }], ["#!/bin/sh", { main_script: true }]].each do |first_line, options|
        io = StringIO.new("#{first_line}\n__END__\n__END__\n#!/usr/bin/env ruby\n42\n__END__\ndata\n")
        result = Ruby::Prism.parse_stream(io, **options)

        assert_predicate result, :success?
        assert_equal 42, result.statement.value
        assert_equal 5, result.statement.location.start_line
        assert_equal 6, result.data_loc.start_line
        assert_equal "data\n", io.read
      end
    end

    def test_ruby_shebang_spanning_stream_reads
      io = StringIO.new("__END__\n#!" + (" " * 4096) + "ruby\n1\n__END__\ndata")
      result = Ruby::Prism.parse_stream(io, command_line: "x")

      assert_predicate result, :success?
      assert_equal 1, result.statement.value
      assert_equal "data", io.read
    end

    def test___END___without_ruby_shebang
      io = StringIO.new("__END__\nno Ruby script here\n")
      result = Ruby::Prism.parse_stream(io, command_line: "x")

      assert_equal [:script_not_found], result.errors.map(&:type)
      assert_predicate io, :eof?
    end

    def test_shebang_in_data_remains_unread
      [
        ["#!ruby", { command_line: "x" }],
        ["#!", { main_script: true }],
        ["\uFEFF#!ruby", { main_script: true }],
        ["\uFEFF#!/bin/sh", { main_script: true }],
        ["#!/bin/sh", { main_script: true, scopes: [[]] }]
      ].each do |first_line, options|
        io = StringIO.new("#{first_line}\n1\n__END__\n#!ruby\n2\n")
        result = Ruby::Prism.parse_stream(io, **options)

        assert_predicate result, :success?
        assert_equal 1, result.statement.value
        assert_equal 1, Ruby::Prism.parse(io.string, **options).statement.value
        assert_equal "#!ruby\n2\n", io.read
      end
    end

    def test_command_line_x_skips_bom_prefixed_shebang
      ["#!ruby", "#!ruby   "].each do |first_line|
        source = "\uFEFF#{first_line}\n1\n__END__\n#!ruby\n2\n__END__\ndata\n"
        io = StringIO.new(source)
        result = Ruby::Prism.parse_stream(io, command_line: "x")

        assert_predicate result, :success?
        assert_equal 2, result.statement.value
        assert_equal 2, Ruby::Prism.parse(source, command_line: "x").statement.value
        assert_equal "data\n", io.read
      end
    end

    def test_initial___END___after_utf8_bom
      io = StringIO.new("\uFEFF__END__\r\ndata\n")
      result = Ruby::Prism.parse_stream(io)

      assert_equal 3, result.data_loc.start_offset
      assert_equal "__END__\r\n", result.data_loc.slice
      assert_equal "data\n", io.read
    end

    def test_false___END___in_percent_string
      io = StringIO.new("p(%\n__END__\n+ %q{hi})\n")
      result = Ruby::Prism.parse_stream(io)

      assert_predicate result, :success?
      assert_nil result.data_loc
      assert_equal "p(%\n__END__\n+ %q{hi})", result.statement.location.slice
    end

    # __END__ as the final line with no trailing newline must still be detected
    # as the terminator. This exercises the EOF check for a chunk that does not
    # end in a newline, distinct from a line longer than the internal read
    # buffer (which also has no trailing newline but is not the end of input).
    def test___END___without_trailing_newline
      io = StringIO.new("1 + 2\n__END__")
      result = Ruby::Prism.parse_stream(io)

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
      result = Ruby::Prism.parse_stream(io)

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
      result = Ruby::Prism.parse_stream(io)

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
      result = Ruby::Prism.parse_stream(io)

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
      result = Ruby::Prism.parse_stream(io)

      assert result.success?
      assert_equal 4, result.value.statements.body.length
    end

    def test_nul_bytes
      io = StringIO.new(<<~RUBY)
        1 # \0\0\0\t
        2 # \0\0\0
        3
      RUBY
      result = Ruby::Prism.parse_stream(io)

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
          result = Ruby::Prism.parse_stream(StringIO.new("\"#{body}\""))

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

      result = Ruby::Prism.parse_stream(stream)
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
        Ruby::Prism.parse_stream(stream)
      end
    end

    # A misbehaving stream whose `gets` returns an empty string instead of nil
    # while never reporting EOF must not loop forever. A well-behaved stream
    # returns nil at EOF, so an empty chunk is treated as the end of input.
    def test_gets_returning_empty_string
      stream = Object.new
      def stream.gets(limit = nil); ""; end
      def stream.eof?; false; end

      result = Timeout.timeout(10) { Ruby::Prism.parse_stream(stream) }
      assert result.success?
    rescue Timeout::Error
      flunk "Ruby::Prism.parse_stream looped forever on a stream returning empty strings"
    end
  end
end
