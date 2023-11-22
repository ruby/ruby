# frozen_string_literal: true

return unless RUBY_VERSION >= '3.0.0'
return if RUBY_ENGINE == 'truffleruby' # needs endless method definition

require 'irb/type_completion/types'
require_relative '../helper'

module TestIRB
  class TypeCompletionTypesTest < TestCase
    def test_type_inspect
      true_type = IRB::TypeCompletion::Types::TRUE
      false_type = IRB::TypeCompletion::Types::FALSE
      nil_type = IRB::TypeCompletion::Types::NIL
      string_type = IRB::TypeCompletion::Types::STRING
      true_or_false = IRB::TypeCompletion::Types::UnionType[true_type, false_type]
      array_type = IRB::TypeCompletion::Types::InstanceType.new Array, { Elem: true_or_false }
      assert_equal 'nil', nil_type.inspect
      assert_equal 'true', true_type.inspect
      assert_equal 'false', false_type.inspect
      assert_equal 'String', string_type.inspect
      assert_equal 'Array', IRB::TypeCompletion::Types::InstanceType.new(Array).inspect
      assert_equal 'true | false', true_or_false.inspect
      assert_equal 'Array[Elem: true | false]', array_type.inspect
      assert_equal 'Array', array_type.inspect_without_params
      assert_equal 'Proc', IRB::TypeCompletion::Types::PROC.inspect
      assert_equal 'Array.itself', IRB::TypeCompletion::Types::SingletonType.new(Array).inspect
    end

    def test_type_from_object
      obj = Object.new
      bo = BasicObject.new
      def bo.hash; 42; end # Needed to use this object as a hash key
      arr = [1, 'a']
      hash = { 'key' => :value }
      int_type = IRB::TypeCompletion::Types.type_from_object 1
      obj_type = IRB::TypeCompletion::Types.type_from_object obj
      arr_type = IRB::TypeCompletion::Types.type_from_object arr
      hash_type = IRB::TypeCompletion::Types.type_from_object hash
      bo_type = IRB::TypeCompletion::Types.type_from_object bo
      bo_arr_type = IRB::TypeCompletion::Types.type_from_object [bo]
      bo_key_hash_type = IRB::TypeCompletion::Types.type_from_object({ bo => 1 })
      bo_value_hash_type = IRB::TypeCompletion::Types.type_from_object({ x: bo })

      assert_equal Integer, int_type.klass
      # Use singleton_class to autocomplete singleton methods
      assert_equal obj.singleton_class, obj_type.klass
      assert_equal Object.instance_method(:singleton_class).bind_call(bo), bo_type.klass
      # Array and Hash are special
      assert_equal Array, arr_type.klass
      assert_equal Array, bo_arr_type.klass
      assert_equal Hash, hash_type.klass
      assert_equal Hash, bo_key_hash_type.klass
      assert_equal Hash, bo_value_hash_type.klass
      assert_equal BasicObject, bo_arr_type.params[:Elem].klass
      assert_equal BasicObject, bo_key_hash_type.params[:K].klass
      assert_equal BasicObject, bo_value_hash_type.params[:V].klass
      assert_equal 'Object', obj_type.inspect
      assert_equal 'Array[Elem: Integer | String]', arr_type.inspect
      assert_equal 'Hash[K: String, V: Symbol]', hash_type.inspect
      assert_equal 'Array.itself', IRB::TypeCompletion::Types.type_from_object(Array).inspect
      assert_equal 'IRB::TypeCompletion.itself', IRB::TypeCompletion::Types.type_from_object(IRB::TypeCompletion).inspect
    end

    def test_type_methods
      s = +''
      class << s
        def foobar; end
        private def foobaz; end
      end
      String.define_method(:foobarbaz) {}
      targets = [:foobar, :foobaz, :foobarbaz]
      type = IRB::TypeCompletion::Types.type_from_object s
      assert_equal [:foobar, :foobarbaz], targets & type.methods
      assert_equal [:foobar, :foobaz, :foobarbaz], targets & type.all_methods
      assert_equal [:foobarbaz], targets & IRB::TypeCompletion::Types::STRING.methods
      assert_equal [:foobarbaz], targets & IRB::TypeCompletion::Types::STRING.all_methods
    ensure
      String.remove_method :foobarbaz
    end

    def test_basic_object_methods
      bo = BasicObject.new
      def bo.foobar; end
      type = IRB::TypeCompletion::Types.type_from_object bo
      assert type.all_methods.include?(:foobar)
    end
  end
end
