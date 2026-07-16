# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class ErrorRecoveryTest < TestCase
    def test_alias_global_variable_node_old_name_symbol
      result = Prism.parse("alias $a b")
      refute result.success?

      node = result.value.statements.body.first
      assert_kind_of ErrorRecoveryNode, node.old_name
      assert_kind_of SymbolNode, node.old_name.unexpected
    end

    def test_alias_global_variable_node_old_name_missing
      result = Prism.parse("alias $a 42")
      refute result.success?

      node = result.value.statements.body.first
      assert_kind_of ErrorRecoveryNode, node.old_name
      assert_nil node.old_name.unexpected
    end

    def test_alias_method_node_old_name_global_variable
      result = Prism.parse("alias a $b")
      refute result.success?

      node = result.value.statements.body.first
      assert_kind_of ErrorRecoveryNode, node.old_name
      assert_kind_of GlobalVariableReadNode, node.old_name.unexpected
    end

    def test_alias_method_node_old_name_missing
      result = Prism.parse("alias a 42")
      refute result.success?

      node = result.value.statements.body.first
      assert_kind_of ErrorRecoveryNode, node.old_name
      assert_nil node.old_name.unexpected
    end

    def test_class_node_constant_path_call
      result = Prism.parse("class 0.X; end")
      refute result.success?

      node = result.value.statements.body.first
      assert_kind_of ErrorRecoveryNode, node.constant_path
      assert_kind_of CallNode, node.constant_path.unexpected
    end

    def test_for_node_index_back_reference
      result = Prism.parse("for $& in a; end")
      refute result.success?

      node = result.value.statements.body.first
      assert_kind_of ErrorRecoveryNode, node.index
      assert_kind_of BackReferenceReadNode, node.index.unexpected
    end

    def test_for_node_index_numbered_reference
      result = Prism.parse("for $1 in a; end")
      refute result.success?

      node = result.value.statements.body.first
      assert_kind_of ErrorRecoveryNode, node.index
      assert_kind_of NumberedReferenceReadNode, node.index.unexpected
    end

    def test_for_node_index_missing
      result = Prism.parse("for in 1..10; end")
      refute result.success?

      node = result.value.statements.body.first
      assert_kind_of ErrorRecoveryNode, node.index
      assert_nil node.index.unexpected
    end

    def test_interpolated_string_node_parts_xstring
      result = Prism.parse("<<~`FOO` \"bar\"\nls\nFOO\n")
      refute result.success?

      node = result.value.statements.body.first
      assert node.parts.any? { |part| part.is_a?(ErrorRecoveryNode) && part.unexpected.is_a?(XStringNode) }
    end

    def test_interpolated_string_node_parts_interpolated_xstring
      result = Prism.parse("<<~`FOO` \"bar\"\n\#{ls}\nFOO\n")
      refute result.success?

      node = result.value.statements.body.first
      assert node.parts.any? { |part| part.is_a?(ErrorRecoveryNode) && part.unexpected.is_a?(InterpolatedXStringNode) }
    end

    def test_module_node_constant_path_def
      result = Prism.parse("module def foo; end")
      refute result.success?

      node = result.value.statements.body.first
      assert_kind_of ErrorRecoveryNode, node.constant_path
      assert_kind_of DefNode, node.constant_path.unexpected
    end

    def test_module_node_constant_path_missing
      result = Prism.parse("module Parent module end")
      refute result.success?

      node = result.value.statements.body.first.body.body.first
      assert_kind_of ErrorRecoveryNode, node.constant_path
      assert_nil node.constant_path.unexpected
    end

    def test_multi_target_node_lefts_back_reference
      result = Prism.parse("a, (b, $&) = z")
      refute result.success?

      node = result.value.statements.body.first.lefts.last
      assert node.lefts.any? { |left| left.is_a?(ErrorRecoveryNode) && left.unexpected.is_a?(BackReferenceReadNode) }
    end

    def test_multi_target_node_lefts_numbered_reference
      result = Prism.parse("a, (b, $1) = z")
      refute result.success?

      node = result.value.statements.body.first.lefts.last
      assert node.lefts.any? { |left| left.is_a?(ErrorRecoveryNode) && left.unexpected.is_a?(NumberedReferenceReadNode) }
    end

    def test_multi_target_node_rights_back_reference
      result = Prism.parse("a, (*, $&) = z")
      refute result.success?

      node = result.value.statements.body.first.lefts.last
      assert node.rights.any? { |right| right.is_a?(ErrorRecoveryNode) && right.unexpected.is_a?(BackReferenceReadNode) }
    end

    def test_multi_target_node_rights_numbered_reference
      result = Prism.parse("a, (*, $1) = z")
      refute result.success?

      node = result.value.statements.body.first.lefts.last
      assert node.rights.any? { |right| right.is_a?(ErrorRecoveryNode) && right.unexpected.is_a?(NumberedReferenceReadNode) }
    end

    def test_multi_write_node_lefts_back_reference
      result = Prism.parse("$&, = z")
      refute result.success?

      node = result.value.statements.body.first
      assert node.lefts.any? { |left| left.is_a?(ErrorRecoveryNode) && left.unexpected.is_a?(BackReferenceReadNode) }
    end

    def test_multi_write_node_lefts_numbered_reference
      result = Prism.parse("$1, = z")
      refute result.success?

      node = result.value.statements.body.first
      assert node.lefts.any? { |left| left.is_a?(ErrorRecoveryNode) && left.unexpected.is_a?(NumberedReferenceReadNode) }
    end

    def test_multi_write_node_rights_back_reference
      result = Prism.parse("*, $& = z")
      refute result.success?

      node = result.value.statements.body.first
      assert node.rights.any? { |right| right.is_a?(ErrorRecoveryNode) && right.unexpected.is_a?(BackReferenceReadNode) }
    end

    def test_multi_write_node_rights_numbered_reference
      result = Prism.parse("*, $1 = z")
      refute result.success?

      node = result.value.statements.body.first
      assert node.rights.any? { |right| right.is_a?(ErrorRecoveryNode) && right.unexpected.is_a?(NumberedReferenceReadNode) }
    end

    def test_parameters_node_posts_keyword_rest
      result = Prism.parse("def f(**kwargs, ...); end")
      refute result.success?

      node = result.value.statements.body.first.parameters
      assert node.posts.any? { |post| post.is_a?(ErrorRecoveryNode) && post.unexpected.is_a?(KeywordRestParameterNode) }
    end

    def test_parameters_node_posts_no_keywords
      result = Prism.parse("def f(**nil, ...); end")
      refute result.success?

      node = result.value.statements.body.first.parameters
      assert node.posts.any? { |post| post.is_a?(ErrorRecoveryNode) && post.unexpected.is_a?(NoKeywordsParameterNode) }
    end

    def test_parameters_node_posts_forwarding
      result = Prism.parse("def f(..., ...); end")
      refute result.success?

      node = result.value.statements.body.first.parameters
      assert node.posts.any? { |post| post.is_a?(ErrorRecoveryNode) && post.unexpected.is_a?(ForwardingParameterNode) }
    end

    def test_pinned_variable_node_variable_missing
      result = Prism.parse("foo in ^Bar")
      refute result.success?

      node = result.value.statements.body.first.pattern
      assert_kind_of ErrorRecoveryNode, node.variable
      assert_nil node.variable.unexpected
    end

    def test_rescue_node_reference_back_reference
      result = Prism.parse("begin; rescue => $&; end")
      refute result.success?

      node = result.value.statements.body.first.rescue_clause
      assert_kind_of ErrorRecoveryNode, node.reference
      assert_kind_of BackReferenceReadNode, node.reference.unexpected
    end

    def test_rescue_node_reference_numbered_reference
      result = Prism.parse("begin; rescue => $1; end")
      refute result.success?

      node = result.value.statements.body.first.rescue_clause
      assert_kind_of ErrorRecoveryNode, node.reference
      assert_kind_of NumberedReferenceReadNode, node.reference.unexpected
    end

    def test_rescue_node_reference_missing
      result = Prism.parse("begin; rescue =>; end")
      refute result.success?

      node = result.value.statements.body.first.rescue_clause
      assert_kind_of ErrorRecoveryNode, node.reference
      assert_nil node.reference.unexpected
    end
  end
end
