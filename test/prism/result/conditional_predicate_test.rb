# frozen_string_literal: true

require_relative "../test_helper"

module Ruby::Prism
  class ConditionalPredicateTest < TestCase
    def test_range_in_parentheses
      assert_kind_of RangeNode, Ruby::Prism.parse_statement("not (; ..stop)").receiver.body.body.last
      assert_kind_of FlipFlopNode, Ruby::Prism.parse_statement("not (..stop;)").receiver.body.body.last

      group = Ruby::Prism.parse_statement("if (setup; (start...stop)); end").predicate
      assert_kind_of RangeNode, group.body.body.last.body.body.last
    end

    def test_logical_operands_in_group_tail
      group = Ruby::Prism.parse_statement("not (()\ngate and ..stop)").receiver
      assert_kind_of FlipFlopNode, group.body.body.last.right

      group = Ruby::Prism.parse_statement("if begin setup; /start/ or ..stop end; end").predicate
      tail = group.statements.body.last
      assert_kind_of MatchLastLineNode, tail.left
      assert_kind_of FlipFlopNode, tail.right
    end

    def test_regexp_in_group_tail
      group = Ruby::Prism.parse_statement("if (/first/; /last/); end").predicate
      first, last = group.body.body
      assert_kind_of RegularExpressionNode, first
      assert_kind_of MatchLastLineNode, last

      group = Ruby::Prism.parse_statement('if begin setup; /#{pattern}/ end; end').predicate
      assert_kind_of InterpolatedMatchLastLineNode, group.statements.body.last
    end

    def test_range_in_begin
      group = Ruby::Prism.parse_statement("if begin; start..stop end; end").predicate
      assert_kind_of RangeNode, group.statements.body.last

      group = Ruby::Prism.parse_statement("if begin start..stop; end; end").predicate
      assert_kind_of FlipFlopNode, group.statements.body.last
    end

    def test_begin_with_exception_clauses
      ["rescue", "ensure"].each do |clause|
        group = Ruby::Prism.parse_statement("if begin /body/; #{clause}; end; end").predicate
        assert_kind_of RegularExpressionNode, group.statements.body.last, clause
      end
    end
  end
end
