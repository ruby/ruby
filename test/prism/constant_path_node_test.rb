# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class ConstantPathNodeTest < TestCase
    def test_full_name_for_constant_path
      source = <<~RUBY
        Foo:: # comment
          Bar::Baz::
            Qux
      RUBY

      constant_path = Prism.parse(source).value.statements.body.first
      assert_equal("Foo::Bar::Baz::Qux", constant_path.full_name)
    end

    def test_full_name_for_constant_path_with_self
      source = <<~RUBY
        self:: # comment
          Bar::Baz::
            Qux
      RUBY

      constant_path = Prism.parse(source).value.statements.body.first
      assert_raise(ConstantPathNode::DynamicPartsInConstantPathError) do
        constant_path.full_name
      end
    end

    def test_full_name_for_constant_path_with_variable
      source = <<~RUBY
        foo:: # comment
          Bar::Baz::
            Qux
      RUBY

      constant_path = Prism.parse(source).value.statements.body.first

      assert_raise(ConstantPathNode::DynamicPartsInConstantPathError) do
        constant_path.full_name
      end
    end

    def test_full_name_for_constant_path_target
      source = <<~RUBY
        Foo:: # comment
          Bar::Baz::
            Qux, Something = [1, 2]
      RUBY

      node = Prism.parse(source).value.statements.body.first
      assert_equal("Foo::Bar::Baz::Qux", node.lefts.first.full_name)
    end

    def test_full_name_for_constant_path_with_stovetop_start
      source = <<~RUBY
        ::Foo:: # comment
          Bar::Baz::
            Qux, Something = [1, 2]
      RUBY

      node = Prism.parse(source).value.statements.body.first
      assert_equal("::Foo::Bar::Baz::Qux", node.lefts.first.full_name)
    end

    def test_full_name_for_constant_path_target_with_non_constant_parent
      source = <<~RUBY
        self::Foo, Bar = [1, 2]
      RUBY

      constant_target = Prism.parse(source).value.statements.body.first
      dynamic, static = constant_target.lefts

      assert_raise(ConstantPathNode::DynamicPartsInConstantPathError) do
        dynamic.full_name
      end

      assert_equal("Bar", static.full_name)
    end

    def test_full_name_for_constant_read_node
      source = <<~RUBY
        Bar
      RUBY

      constant = Prism.parse(source).value.statements.body.first
      assert_equal("Bar", constant.full_name)
    end
  end
end
