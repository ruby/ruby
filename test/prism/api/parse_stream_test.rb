# frozen_string_literal: true

require_relative "../test_helper"

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
  end
end
