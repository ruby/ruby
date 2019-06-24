# frozen_string_literal: false
require 'test/unit'
require 'forwardable'

class TestForwardable < Test::Unit::TestCase
  INTEGER = 42
  RECEIVER = BasicObject.new
  RETURNED1 = BasicObject.new
  RETURNED2 = BasicObject.new

  class << RECEIVER
    def delegated1
      RETURNED1
    end

    def delegated2
      RETURNED2
    end
  end

  def test_def_instance_delegator
    %i[def_delegator def_instance_delegator].each do |m|
      cls = forwardable_class do
        __send__ m, :@receiver, :delegated1
      end

      assert_same RETURNED1, cls.new.delegated1
    end
  end

  def test_def_instance_delegator_constant
    %i[def_delegator def_instance_delegator].each do |m|
      cls = forwardable_class do
        __send__ m, 'TestForwardable::INTEGER', :to_i
      end

      assert_equal 42, cls.new.to_i
    end
  end

  def test_def_instance_delegator_using_args_method_as_receiver
    %i[def_delegator def_instance_delegator].each do |m|
      cls = forwardable_class(
        receiver_name: :args,
        type: :method,
        visibility: :private
      ) do
        __send__ m, :args, :delegated1
      end

      assert_same RETURNED1, cls.new.delegated1
    end
  end

  def test_def_instance_delegator_using_block_method_as_receiver
    %i[def_delegator def_instance_delegator].each do |m|
      cls = forwardable_class(
        receiver_name: :block,
        type: :method,
        visibility: :private
      ) do
        __send__ m, :block, :delegated1
      end

      assert_same RETURNED1, cls.new.delegated1
    end
  end

  def test_def_instance_delegators
    %i[def_delegators def_instance_delegators].each do |m|
      cls = forwardable_class do
        __send__ m, :@receiver, :delegated1, :delegated2
      end

      assert_same RETURNED1, cls.new.delegated1
      assert_same RETURNED2, cls.new.delegated2
    end
  end

  def test_def_instance_delegators_using_args_method_as_receiver
    %i[def_delegators def_instance_delegators].each do |m|
      cls = forwardable_class(
        receiver_name: :args,
        type: :method,
        visibility: :private
      ) do
        __send__ m, :args, :delegated1, :delegated2
      end

      assert_same RETURNED1, cls.new.delegated1
      assert_same RETURNED2, cls.new.delegated2
    end
  end

  def test_def_instance_delegators_using_block_method_as_receiver
    %i[def_delegators def_instance_delegators].each do |m|
      cls = forwardable_class(
        receiver_name: :block,
        type: :method,
        visibility: :private
      ) do
        __send__ m, :block, :delegated1, :delegated2
      end

      assert_same RETURNED1, cls.new.delegated1
      assert_same RETURNED2, cls.new.delegated2
    end
  end

  def test_instance_delegate
    %i[delegate instance_delegate].each do |m|
      cls = forwardable_class do
        __send__ m, delegated1: :@receiver, delegated2: :@receiver
      end

      assert_same RETURNED1, cls.new.delegated1
      assert_same RETURNED2, cls.new.delegated2

      cls = forwardable_class do
        __send__ m, %i[delegated1 delegated2] => :@receiver
      end

      assert_same RETURNED1, cls.new.delegated1
      assert_same RETURNED2, cls.new.delegated2
    end
  end

  def test_def_instance_delegate_using_args_method_as_receiver
    %i[delegate instance_delegate].each do |m|
      cls = forwardable_class(
        receiver_name: :args,
        type: :method,
        visibility: :private
      ) do
        __send__ m, delegated1: :args, delegated2: :args
      end

      assert_same RETURNED1, cls.new.delegated1
      assert_same RETURNED2, cls.new.delegated2
    end
  end

  def test_def_instance_delegate_using_block_method_as_receiver
    %i[delegate instance_delegate].each do |m|
      cls = forwardable_class(
        receiver_name: :block,
        type: :method,
        visibility: :private
      ) do
        __send__ m, delegated1: :block, delegated2: :block
      end

      assert_same RETURNED1, cls.new.delegated1
      assert_same RETURNED2, cls.new.delegated2
    end
  end

  def test_class_single_delegator
    %i[def_delegator def_single_delegator].each do |m|
      cls = single_forwardable_class do
        __send__ m, :@receiver, :delegated1
      end

      assert_same RETURNED1, cls.delegated1
    end
  end

  def test_class_single_delegators
    %i[def_delegators def_single_delegators].each do |m|
      cls = single_forwardable_class do
        __send__ m, :@receiver, :delegated1, :delegated2
      end

      assert_same RETURNED1, cls.delegated1
      assert_same RETURNED2, cls.delegated2
    end
  end

  def test_class_single_delegate
    %i[delegate single_delegate].each do |m|
      cls = single_forwardable_class do
        __send__ m, delegated1: :@receiver, delegated2: :@receiver
      end

      assert_same RETURNED1, cls.delegated1
      assert_same RETURNED2, cls.delegated2

      cls = single_forwardable_class do
        __send__ m, %i[delegated1 delegated2] => :@receiver
      end

      assert_same RETURNED1, cls.delegated1
      assert_same RETURNED2, cls.delegated2
    end
  end

  def test_obj_single_delegator
    %i[def_delegator def_single_delegator].each do |m|
      obj = single_forwardable_object do
        __send__ m, :@receiver, :delegated1
      end

      assert_same RETURNED1, obj.delegated1
    end
  end

  def test_obj_single_delegators
    %i[def_delegators def_single_delegators].each do |m|
      obj = single_forwardable_object do
        __send__ m, :@receiver, :delegated1, :delegated2
      end

      assert_same RETURNED1, obj.delegated1
      assert_same RETURNED2, obj.delegated2
    end
  end

  def test_obj_single_delegate
    %i[delegate single_delegate].each do |m|
      obj = single_forwardable_object do
        __send__ m, delegated1: :@receiver, delegated2: :@receiver
      end

      assert_same RETURNED1, obj.delegated1
      assert_same RETURNED2, obj.delegated2

      obj = single_forwardable_object do
        __send__ m, %i[delegated1 delegated2] => :@receiver
      end

      assert_same RETURNED1, obj.delegated1
      assert_same RETURNED2, obj.delegated2
    end
  end

  class Foo
    extend Forwardable

    attr_accessor :bar
    def_delegator :bar, :baz
    def_delegator :caller, :itself, :c
  end

  def test_backtrace_adjustment
    obj = Foo.new
    def (obj.bar = Object.new).baz
      foo
    end
    e = assert_raise(NameError) {
      obj.baz
    }
    assert_not_match(/\/forwardable\.rb/, e.backtrace[0],
                     proc {RubyVM::InstructionSequence.of(obj.method(:baz)).disassemble})
    assert_equal(caller(0, 1)[0], Foo.new.c[0])
  end

  class Foo2 < BasicObject
    extend ::Forwardable

    def_delegator :bar, :baz
  end

  def test_basicobject_subclass
    bug11616 = '[ruby-core:71176] [Bug #11616]'
    assert_raise_with_message(NameError, /`bar'/, bug11616) {
      Foo2.new.baz
    }
  end

  def test_aref
    obj = Object.new.extend SingleForwardable
    obj.instance_variable_set("@h", {foo: 42})
    obj.def_delegator("@h", :[])
    assert_equal(42, obj[:foo])
  end

  def test_aset
    obj = Object.new.extend SingleForwardable
    obj.instance_variable_set("@h", h = {foo: 0})
    obj.def_delegator("@h", :[]=)
    obj[:foo] = 42
    assert_equal(42, h[:foo])
  end

  def test_binop
    obj = Object.new.extend SingleForwardable
    obj.instance_variable_set("@h", 40)
    obj.def_delegator("@h", :+)
    assert_equal(42, obj+2)
  end

  def test_uniop
    obj = Object.new.extend SingleForwardable
    obj.instance_variable_set("@h", -42)
    obj.def_delegator("@h", :-@)
    assert_equal(42, -obj)
  end

  def test_on_private_method
    cls = Class.new do
      private def foo; :foo end
      extend Forwardable
      def_delegator :itself, :foo, :bar
    end
    assert_warn(/forwarding to private method/) do
      assert_equal(:foo, cls.new.bar)
    end
  end

  def test_non_module
    str = String.new
    str.extend Forwardable
    str.instance_variable_set("@h", 42)
    str.def_delegator("@h", :to_s, :forty_two)
    assert_equal("42", str.forty_two)
  end

  private

  def forwardable_class(
    receiver_name: :receiver,
    type: :ivar,
    visibility: :public,
    &block
  )
    Class.new do
      extend Forwardable

      define_method(:initialize) do
        instance_variable_set("@#{receiver_name}", RECEIVER)
      end

      if type == :method
        attr_reader(receiver_name)
        __send__(visibility, receiver_name)
      end

      class_exec(&block)
    end
  end

  def single_forwardable_class(&block)
    Class.new do
      extend SingleForwardable

      @receiver = RECEIVER

      class_exec(&block)
    end
  end

  def single_forwardable_object(&block)
    obj = Object.new.extend SingleForwardable
    obj.instance_variable_set(:@receiver, RECEIVER)
    obj.instance_eval(&block)
    obj
  end
end
