# frozen_string_literal: true

require_relative "../test_helper"

module Ruby::Prism
  # The lexer tracks whether a `do` closes a loop predicate and whether a `do`
  # can open a block on stacks with one frame per open delimiter. These tests
  # nest delimiters around and across the 64-frame words those stacks spill
  # into, and check that the frame beneath the delimiters is still read once
  # they close.
  class DelimiterNestingTest < TestCase
    DEPTHS = [1, 31, 32, 33, 63, 64, 65, 127, 128, 129, 200, 1000]

    def test_loop_predicate
      DEPTHS.each do |depth|
        source = "while #{"(" * depth}x#{")" * depth} do end"
        assert_loop(WhileNode, source)
      end
    end

    def test_mixed_delimiters
      DEPTHS.each do |depth|
        opening = "([" * depth
        closing = "])" * depth
        source = "until #{opening}x#{closing} do end"
        assert_loop(UntilNode, source)
      end
    end

    def test_nested_loop_predicate
      DEPTHS.each do |depth|
        inner = "while #{"(" * depth}y#{")" * depth} do end"
        source = "while #{"(" * depth}#{inner}#{")" * depth} do end"

        node = assert_loop(WhileNode, source)
        assert_kind_of WhileNode, node.predicate.breadth_first_search { |child| child.is_a?(WhileNode) }
      end
    end

    def test_block_inside_loop_predicate
      DEPTHS.each do |depth|
        source = "while #{"(" * depth}foo do end#{")" * depth} do end"

        node = assert_loop(WhileNode, source)
        call = node.predicate.breadth_first_search { |child| child.is_a?(CallNode) }
        assert_kind_of BlockNode, call.block
      end
    end

    # A closing delimiter without a matching opening one still pops both
    # stacks, so these pop an empty stack, some of them more than 64 times in
    # a row, and check that the source still parses with errors.
    def test_unmatched_closers
      sources = [")", "foo]", "}", "def foo; ); end", "while x) do end", ")" * 100, "]" * 100, "}" * 100]

      sources.each do |source|
        refute_empty Ruby::Prism.parse(source).errors, source
      end
    end

    private

    def assert_loop(type, source)
      result = Ruby::Prism.parse(source)
      assert_empty result.errors, source

      node = result.value.statements.body.first
      assert_kind_of type, node
      node
    end
  end
end
