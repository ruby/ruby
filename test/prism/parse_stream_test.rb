# frozen_string_literal: true

require_relative "test_helper"
require "stringio"

module Prism
  class ParseStreamTest < TestCase
    def test_single_line
      io = StringIO.new("1 + 2")
      result = Prism.parse_stream(io)

      assert result.success?
      assert_kind_of Prism::CallNode, result.value.statements.body.first
    end

    def test_multi_line
      io = StringIO.new("1 + 2\n3 + 4")
      result = Prism.parse_stream(io)

      assert result.success?
      assert_kind_of Prism::CallNode, result.value.statements.body.first
      assert_kind_of Prism::CallNode, result.value.statements.body.last
    end

    def test_multi_read
      io = StringIO.new("a" * 4096 * 4)
      result = Prism.parse_stream(io)

      assert result.success?
      assert_kind_of Prism::CallNode, result.value.statements.body.first
    end

    def test___END__
      io = StringIO.new("1 + 2\n3 + 4\n__END__\n5 + 6")
      result = Prism.parse_stream(io)

      assert result.success?
      assert_equal 2, result.value.statements.body.length
      assert_equal "5 + 6", io.read
    end

    def test_false___END___in_string
      io = StringIO.new("1 + 2\n3 + 4\n\"\n__END__\n\"\n5 + 6")
      result = Prism.parse_stream(io)

      assert result.success?
      assert_equal 4, result.value.statements.body.length
    end

    def test_false___END___in_regexp
      io = StringIO.new("1 + 2\n3 + 4\n/\n__END__\n/\n5 + 6")
      result = Prism.parse_stream(io)

      assert result.success?
      assert_equal 4, result.value.statements.body.length
    end

    def test_false___END___in_list
      io = StringIO.new("1 + 2\n3 + 4\n%w[\n__END__\n]\n5 + 6")
      result = Prism.parse_stream(io)

      assert result.success?
      assert_equal 4, result.value.statements.body.length
    end

    def test_false___END___in_heredoc
      io = StringIO.new("1 + 2\n3 + 4\n<<-EOF\n__END__\nEOF\n5 + 6")
      result = Prism.parse_stream(io)

      assert result.success?
      assert_equal 4, result.value.statements.body.length
    end
  end
end
