# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class ImplicitArrayTest < TestCase
    def test_call_node
      assert_implicit_array("a.a = *b")
      assert_implicit_array("a.a = 1, 2, 3")
      assert_implicit_array("a[a] = *b")
      assert_implicit_array("a[a] = 1, 2, 3")
    end

    def test_class_variable_write_node
      assert_implicit_array("@@a = *b")
      assert_implicit_array("@@a = 1, 2, 3")
    end

    def test_constant_path_write_node
      assert_implicit_array("A::A = *b")
      assert_implicit_array("A::A = 1, 2, 3")
    end

    def test_constant_write_node
      assert_implicit_array("A = *b")
      assert_implicit_array("A = 1, 2, 3")
    end

    def test_global_variable_write_node
      assert_implicit_array("$a = *b")
      assert_implicit_array("$a = 1, 2, 3")
    end

    def test_instance_variable_write_node
      assert_implicit_array("@a = *b")
      assert_implicit_array("@a = 1, 2, 3")
    end

    def test_local_variable_write_node
      assert_implicit_array("a = *b")
      assert_implicit_array("a = 1, 2, 3")
    end

    def test_multi_write_node
      assert_implicit_array("a, b, c = *b")
      assert_implicit_array("a, b, c = 1, 2, 3")
    end

    private

    def assert_implicit_array(source)
      assert Prism.parse_success?(source)
      assert Prism.parse_failure?("if #{source} then end")

      assert_valid_syntax(source)
      refute_valid_syntax("if #{source} then end")
    end
  end
end
