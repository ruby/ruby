# frozen_string_literal: false
require 'test/unit'

class TestLogicalOpHook < Test::Unit::TestCase
  Node = Struct.new(:op, :lhs, :rhs)

  module Ext
    refine Node do
      define_method(:"&&") { |other| Node.new(:and, self, other) }
      define_method(:"||") { |other| Node.new(:or, self, other) }
    end

    refine NilClass do
      define_method(:"&&") { |other| [:nil_and, other] }
      define_method(:"||") { |other| [:nil_or, other] }
    end

    refine TrueClass do
      define_method(:"&&") { |other| [:true_and, other] }
      define_method(:"||") { |other| [:true_or, other] }
    end
  end

  class GloballyDefined
    define_method(:"&&") { |other| :hooked }
    define_method(:"||") { |other| :hooked }
  end

  LHS_VALUES = [1, "str", :sym, Object.new, Node.new(:leaf), true, false, nil]

  def self.plain_and(log, a) = a && (log << :rhs; :b)
  def self.plain_or(log, a) = a || (log << :rhs; :b)
end

using TestLogicalOpHook::Ext

class TestLogicalOpHook
  def refined_and(log, a) = a && (log << :rhs; :b)
  def refined_or(log, a) = a || (log << :rhs; :b)

  def test_unrefined_scope
    LHS_VALUES.each do |a|
      log = []
      assert_equal(a ? :b : a, self.class.plain_and(log, a))
      assert_equal(a ? [:rhs] : [], log)
      log = []
      assert_equal(a ? a : :b, self.class.plain_or(log, a))
      assert_equal(a ? [] : [:rhs], log)
    end
  end

  def test_node
    a, b, c = Node.new(:a), Node.new(:b), Node.new(:c)
    assert_equal(Node.new(:and, a, b), a && b)
    assert_equal(Node.new(:or, a, b), a || b)
    assert_equal(Node.new(:and, a, Node.new(:or, b, c)), a && (b || c))
    assert_equal(Node.new(:or, a, Node.new(:and, b, c)), a || b && c)
  end

  def test_left_associative
    a, b, c = Node.new(:a), Node.new(:b), Node.new(:c)
    assert_equal(Node.new(:and, Node.new(:and, a, b), c), a && b && c)
    assert_equal(Node.new(:or, Node.new(:or, a, b), c), a || b || c)
    assert_equal(Node.new(:and, a, Node.new(:and, b, c)), a && (b && c))
    assert_equal(Node.new(:and, Node.new(:and, a, b), c), (a && b and c))
    assert_equal(Node.new(:and, a, Node.new(:and, b, c)), (a and b && c))
  end

  def test_keywords
    a, b = Node.new(:a), Node.new(:b)
    assert_equal(Node.new(:and, a, b), (a and b))
    assert_equal(Node.new(:or, a, b), (a or b))
  end

  def test_evaluation
    [
      [1, :b, [:rhs], 1, []],
      [Node.new(:a), Node.new(:and, Node.new(:a), :b), [:rhs], Node.new(:or, Node.new(:a), :b), [:rhs]],
      [nil, [:nil_and, :b], [:rhs], [:nil_or, :b], [:rhs]],
      [true, [:true_and, :b], [:rhs], [:true_or, :b], [:rhs]],
      [false, false, [], :b, [:rhs]],
    ].each do |a, and_result, and_log, or_result, or_log|
      log = []
      assert_equal(and_result, refined_and(log, a), "#{a.inspect} && b")
      assert_equal(and_log, log, "#{a.inspect} && b")
      log = []
      assert_equal(or_result, refined_or(log, a), "#{a.inspect} || b")
      assert_equal(or_log, log, "#{a.inspect} || b")
    end
  end

  def test_popped
    log = []
    nil && (log << :and)
    true || (log << :or)
    false && (log << :not_evaluated)
    assert_equal([:and, :or], log)
  end

  def test_condition
    log = []
    assert_equal(:then, (nil && (log << :rhs; false)) ? :then : :else)
    assert_equal([:rhs], log)
    assert_equal(:then, if nil && false then :then else :else end)
    assert_equal(:else, unless true || nil then :then else :else end)
    i = 0
    i += 1 while i < 3 && nil
    assert_equal(3, i)
    assert_equal(:else, if false && true then :then else :else end)
    assert_equal(:then, if 1 && 2 then :then else :else end)
  end

  def test_polymorphic_site
    results = [1, Node.new(:a), nil, false, true, Object.new].map { |a| a && :b }
    assert_equal([:b, Node.new(:and, Node.new(:a), :b), [:nil_and, :b], false, [:true_and, :b], :b], results)
  end

  def test_op_assign_unaffected
    x = nil
    x &&= 1
    assert_nil(x)
    y = Node.new(:a)
    y ||= 1
    assert_equal(Node.new(:a), y)
    z = true
    z ||= 1
    assert_equal(true, z)
  end

  def test_global_definition_is_inert
    o = GloballyDefined.new
    log = []
    assert_equal(:b, refined_and(log, o))
    assert_equal([:rhs], log)
    log = []
    assert_same(o, refined_or(log, o))
    assert_equal([], log)
    assert_equal(:hooked, o.send(:"&&", 1))
  end

  def test_hook_defined_after_jit_compilation
    jit_opts = []
    jit_opts << %w[--yjit-call-threshold=1] if defined?(RubyVM::YJIT)
    jit_opts << %w[--zjit-call-threshold=1] if defined?(RubyVM::ZJIT)
    omit "no JIT" if jit_opts.empty?
    jit_opts.each do |opts|
      assert_separately(opts, <<~'RUBY')
        Node = Struct.new(:x)
        module Ext
          refine(Node) {}
        end
        using Ext
        def and_op(a) = a && :b
        def or_op(a) = a || :b
        def cond(a) = (a && false) ? :then : :else
        3.times do
          [Node.new(1), nil].each { |a| and_op(a); or_op(a); cond(a) }
        end
        module Ext
          refine(Node) do
            define_method(:"&&") { |o| [:and, o] }
            define_method(:"||") { |o| [:or, o] }
          end
        end
        3.times do
          assert_equal([:and, :b], and_op(Node.new(1)))
          assert_equal([:or, :b], or_op(Node.new(1)))
          assert_equal(:then, cond(Node.new(1)))
          assert_nil(and_op(nil))
          assert_equal(:b, or_op(nil))
          assert_equal(:else, cond(nil))
        end
        values = [1, "s", :sym, 1.0, [], {}, Object.new, true, false, nil, Node.new(1)]
        3.times do
          values.each do |a|
            if a.is_a?(Node)
              assert_equal([:and, :b], and_op(a))
              assert_equal([:or, :b], or_op(a))
            else
              assert_equal((a ? :b : a), and_op(a))
              assert_equal((a ? a : :b), or_op(a))
            end
          end
        end
      RUBY
    end
  end

  def test_hook_removed_while_evaluating_rhs
    jit_opts = [[]]
    jit_opts << %w[--yjit-call-threshold=1] if defined?(RubyVM::YJIT)
    jit_opts << %w[--zjit-call-threshold=1] if defined?(RubyVM::ZJIT)
    jit_opts.each do |opts|
      assert_separately(opts, <<~'RUBY')
        module Ext
          refine(NilClass) { define_method(:"&&") { |o| [:and, o] } }
        end
        using Ext
        def and_op(a, remove) = a && (Ext.refinements[0].send(:remove_method, :"&&") if remove; :b)
        assert_equal([:and, :b], and_op(nil, false))
        assert_nil(and_op(nil, true))
        assert_nil(and_op(nil, false))
      RUBY
    end
  end

  def test_delegate_class
    require 'delegate'
    klass = DelegateClass(Object)
    d = klass.new(Object.new)
    assert_equal(:b, d && :b)
    assert_same(d, d || :b)
  end
end
