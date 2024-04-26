# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class RedundantReturnTest < TestCase
    def test_statements
      assert_redundant_return("def foo; return; end")
      refute_redundant_return("def foo; return; 1; end")
    end

    def test_begin_implicit
      assert_redundant_return("def foo; return; rescue; end")
      refute_redundant_return("def foo; return; 1; rescue; end")
      refute_redundant_return("def foo; return; rescue; else; end")
    end

    def test_begin_explicit
      assert_redundant_return("def foo; begin; return; rescue; end; end")
      refute_redundant_return("def foo; begin; return; 1; rescue; end; end")
      refute_redundant_return("def foo; begin; return; rescue; else; end; end")
    end

    def test_if
      assert_redundant_return("def foo; return if bar; end")
    end

    def test_unless
      assert_redundant_return("def foo; return unless bar; end")
    end

    def test_else
      assert_redundant_return("def foo; if bar; baz; else; return; end; end")
    end

    def test_case_when
      assert_redundant_return("def foo; case bar; when baz; return; end; end")
    end

    def test_case_else
      assert_redundant_return("def foo; case bar; when baz; else; return; end; end")
    end

    def test_case_match_in
      assert_redundant_return("def foo; case bar; in baz; return; end; end")
    end

    def test_case_match_else
      assert_redundant_return("def foo; case bar; in baz; else; return; end; end")
    end

    private

    def assert_redundant_return(source)
      assert find_return(source).redundant?
    end

    def refute_redundant_return(source)
      refute find_return(source).redundant?
    end

    def find_return(source)
      queue = [Prism.parse(source).value]

      while (current = queue.shift)
        return current if current.is_a?(ReturnNode)
        queue.concat(current.compact_child_nodes)
      end

      flunk "Could not find return node in #{node.inspect}"
    end
  end
end
