# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class TunnelTest < TestCase
    def test_tunnel
      program = Prism.parse("foo(1) +\n  bar(2, 3) +\n  baz(3, 4, 5)").value

      tunnel = program.tunnel(1, 4).last
      assert_kind_of IntegerNode, tunnel
      assert_equal 1, tunnel.value

      tunnel = program.tunnel(2, 6).last
      assert_kind_of IntegerNode, tunnel
      assert_equal 2, tunnel.value

      tunnel = program.tunnel(3, 9).last
      assert_kind_of IntegerNode, tunnel
      assert_equal 4, tunnel.value

      tunnel = program.tunnel(3, 8)
      assert_equal [ProgramNode, StatementsNode, CallNode, ArgumentsNode, CallNode, ArgumentsNode], tunnel.map(&:class)
    end
  end
end
