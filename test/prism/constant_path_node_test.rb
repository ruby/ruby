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

    def test_full_name_for_constant_path_target
      source = <<~RUBY
        Foo:: # comment
          Bar::Baz::
            Qux, Something = [1, 2]
      RUBY

      node = Prism.parse(source).value.statements.body.first
      target = node.targets.first
      assert_equal("Foo::Bar::Baz::Qux", target.full_name)
    end
  end
end
