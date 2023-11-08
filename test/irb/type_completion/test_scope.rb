# frozen_string_literal: true

return unless RUBY_VERSION >= '3.0.0'
return if RUBY_ENGINE == 'truffleruby' # needs endless method definition

require 'irb/type_completion/scope'
require_relative '../helper'

module TestIRB
  class TypeCompletionScopeTest < TestCase
    A, B, C, D, E, F, G, H, I, J, K = ('A'..'K').map do |name|
      klass = Class.new
      klass.define_singleton_method(:inspect) { name }
      IRB::TypeCompletion::Types::InstanceType.new(klass)
    end

    def assert_type(expected_types, type)
      assert_equal [*expected_types].map(&:klass).to_set, type.types.map(&:klass).to_set
    end

    def table(*local_variable_names)
      local_variable_names.to_h { [_1, IRB::TypeCompletion::Types::NIL] }
    end

    def base_scope
      IRB::TypeCompletion::RootScope.new(binding, Object.new, [])
    end

    def test_lvar
      scope = IRB::TypeCompletion::Scope.new base_scope, table('a')
      scope['a'] = A
      assert_equal A, scope['a']
    end

    def test_conditional
      scope = IRB::TypeCompletion::Scope.new base_scope, table('a')
      scope.conditional do |sub_scope|
        sub_scope['a'] = A
      end
      assert_type [A, IRB::TypeCompletion::Types::NIL], scope['a']
    end

    def test_branch
      scope = IRB::TypeCompletion::Scope.new base_scope, table('a', 'b', 'c', 'd')
      scope['c'] = A
      scope['d'] = B
      scope.run_branches(
        -> { _1['a'] = _1['c'] = _1['d'] = C },
        -> { _1['a'] = _1['b'] = _1['d'] = D },
        -> { _1['a'] = _1['b'] = _1['d'] = E },
        -> { _1['a'] = _1['b'] = _1['c'] = F; _1.terminate }
      )
      assert_type [C, D, E], scope['a']
      assert_type [IRB::TypeCompletion::Types::NIL, D, E], scope['b']
      assert_type [A, C], scope['c']
      assert_type [C, D, E], scope['d']
    end

    def test_scope_local_variables
      scope1 = IRB::TypeCompletion::Scope.new base_scope, table('a', 'b')
      scope2 = IRB::TypeCompletion::Scope.new scope1, table('b', 'c'), trace_lvar: false
      scope3 = IRB::TypeCompletion::Scope.new scope2, table('c', 'd')
      scope4 = IRB::TypeCompletion::Scope.new scope2, table('d', 'e')
      assert_empty base_scope.local_variables
      assert_equal %w[a b], scope1.local_variables.sort
      assert_equal %w[b c], scope2.local_variables.sort
      assert_equal %w[b c d], scope3.local_variables.sort
      assert_equal %w[b c d e], scope4.local_variables.sort
    end

    def test_nested_scope
      scope = IRB::TypeCompletion::Scope.new base_scope, table('a', 'b', 'c')
      scope['a'] = A
      scope['b'] = A
      scope['c'] = A
      sub_scope = IRB::TypeCompletion::Scope.new scope, { 'c' => B }
      assert_type A, sub_scope['a']

      assert_type A, sub_scope['b']
      assert_type B, sub_scope['c']
      sub_scope['a'] = C
      sub_scope.conditional { _1['b'] = C }
      sub_scope['c'] = C
      assert_type C, sub_scope['a']
      assert_type [A, C], sub_scope['b']
      assert_type C, sub_scope['c']
      scope.update sub_scope
      assert_type C, scope['a']
      assert_type [A, C], scope['b']
      assert_type A, scope['c']
    end

    def test_break
      scope = IRB::TypeCompletion::Scope.new base_scope, table('a')
      scope['a'] = A
      breakable_scope = IRB::TypeCompletion::Scope.new scope, { IRB::TypeCompletion::Scope::BREAK_RESULT => nil }
      breakable_scope.conditional do |sub|
        sub['a'] = B
        assert_type [B], sub['a']
        sub.terminate_with IRB::TypeCompletion::Scope::BREAK_RESULT, C
        sub['a'] = C
        assert_type [C], sub['a']
      end
      assert_type [A], breakable_scope['a']
      breakable_scope[IRB::TypeCompletion::Scope::BREAK_RESULT] = D
      breakable_scope.merge_jumps
      assert_type [C, D], breakable_scope[IRB::TypeCompletion::Scope::BREAK_RESULT]
      scope.update breakable_scope
      assert_type [A, B], scope['a']
    end
  end
end
