# frozen_string_literal: true
require 'test/unit'

class Test_Load_ResolveSymbol < Test::Unit::TestCase
  def test_load_resolve_symbol_resolver
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      feature = "Feature #20005"
      assert_raise(LoadError, "resolve_symbol_target is not loaded") {
        require '-test-/load/resolve_symbol_resolver'
      }
      require '-test-/load/resolve_symbol_target'
      assert_nothing_raised(LoadError, "#{feature} resolver can be loaded") {
        require '-test-/load/resolve_symbol_resolver'
      }
      assert_not_nil ResolveSymbolResolver
      assert_equal "from target", ResolveSymbolResolver.any_method

      assert_raise(LoadError, "tries to resolve missing feature name, and it should raise LoadError") {
        ResolveSymbolResolver.try_resolve_fname
      }
      assert_raise(LoadError, "tries to resolve missing symbol name, and it should raise LoadError") {
        ResolveSymbolResolver.try_resolve_sname
      }
    end;
  end
end
