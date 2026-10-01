# frozen_string_literal: false
require 'test/unit'

class TestLogicalOpHook < Test::Unit::TestCase
  Node = Struct.new(:op, :lhs, :rhs)

  module Ext
    refine Node do
      def &&(other) = Node.new(:and, self, other)
      def ||(other) = Node.new(:or, self, other)
      alias andop &&
    end

    refine NilClass do
      def &&(other) = [:nil_and, other]
      def ||(other) = [:nil_or, other]
    end

    refine TrueClass do
      def &&(other) = [:true_and, other]
      def ||(other) = [:true_or, other]
    end
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

  def test_statement_unhooked
    log = []
    nil && (log << :not_evaluated)
    true || (log << :not_evaluated)
    Node.new(:a) && (log << :rhs)
    assert_equal([:rhs], log)
  end

  def test_condition_unhooked
    log = []
    assert_equal(:else, (nil && (log << :rhs; false)) ? :then : :else)
    assert_empty(log)
    assert_equal(:else, if nil && false then :then else :else end)
    assert_equal(:else, if (nil || false) then :then else :else end)
    assert_equal(:then, unless nil || false then :then else :else end)
    assert_equal(:else, if nil || nil and true then :then else :else end)
    i = 0
    i += 1 while i < 3 && nil
    assert_equal(0, i)
    assert_equal(:then, if 1 && 2 then :then else :else end)
    assert_equal(false, !(nil && false))
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

  def test_definition_outside_refinement
    c = Class.new
    assert_raise_with_message(NameError, "'&&' can be defined only in refinements") do
      c.class_eval { def &&(other) = 1 }
    end
    assert_raise(NameError) { c.class_eval { def ||(other) = 1 } }
    assert_raise(NameError) { c.class_eval { def self.&&(other) = 1 } }
    assert_raise(NameError) { c.class_eval { define_method(:"||") { |other| } } }
    assert_raise(NameError) { c.class_eval { alias_method :"&&", :to_s } }
    assert_raise(NameError) { Object.new.define_singleton_method(:"&&") { |other| } }
    assert_raise(NameError) { Module.new { def ||(other) = 1 } }
    assert_not_send([c, :method_defined?, :&&])
    assert_not_send([c, :method_defined?, :||])
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
            def &&(o) = [:and, o]
            def ||(o) = [:or, o]
          end
        end
        3.times do
          assert_equal([:and, :b], and_op(Node.new(1)))
          assert_equal([:or, :b], or_op(Node.new(1)))
          assert_equal(:else, cond(Node.new(1)))
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

  def test_megamorphic_site
    jit_opts = [[]]
    jit_opts << %w[--yjit-call-threshold=2] if defined?(RubyVM::YJIT)
    jit_opts << %w[--zjit-call-threshold=2] if defined?(RubyVM::ZJIT)
    jit_opts.each do |opts|
      assert_separately(opts, <<~'RUBY')
        Node = Struct.new(:x)
        module Ext
          refine(Node) do
            def &&(o) = [:and, o]
            def ||(o) = [:or, o]
          end
        end
        using Ext
        def and_op(a) = a && :b
        def or_op(a) = a || :b
        def cond(a, b = 1) = (a && b) ? :then : :else
        values = [1, "s", :sym, 1.0, [], {}, Object.new, 1..2, true, false, nil, Node.new(1)]
        5.times do
          values.each do |a|
            if a.is_a?(Node)
              assert_equal([:and, :b], and_op(a))
              assert_equal([:or, :b], or_op(a))
              assert_equal(:then, cond(a))
            else
              assert_same((a ? :b : a), and_op(a))
              assert_same((a ? a : :b), or_op(a))
              assert_equal((a ? :then : :else), cond(a))
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
          refine(NilClass) { def &&(o) = [:and, o] }
        end
        using Ext
        def and_op(a, remove) = a && (Ext.refinements[0].send(:remove_method, :"&&") if remove; :b)
        assert_equal([:and, :b], and_op(nil, false))
        assert_nil(and_op(nil, true))
        assert_nil(and_op(nil, false))
      RUBY
    end
  end

  def test_syntax
    assert_equal(:"&&", :&&)
    assert_equal(:"||", :||)
    assert_equal([:"&&", :"||"], %i[&& ||])
    assert_equal(":&&", :&&.inspect)
    assert_equal(":||", :||.inspect)
    assert_equal(':"&&&"', :"&&&".inspect)
    assert_equal(':"||="', :"||=".inspect)
    assert_equal(:"&&", true ? :&& : :||)

    n = Node.new(:a)
    assert_equal(Node.new(:and, n, 1), n.&&(1))
    assert_equal(Node.new(:or, n, 2), n.||(2))
    assert_equal(Node.new(:and, n, 3), n.andop(3))
    assert_equal(Node.new(:and, n, 4), n::&&(4))
    assert_raise(NameError) { Class.new { undef &&, || } }

    assert_equal([3], [1].map { || 3 })
    assert_equal(1, [1].each { |a| break a })
  end

  def test_delegate_class
    require 'delegate'
    klass = DelegateClass(Object)
    d = klass.new(Object.new)
    assert_equal(:b, d && :b)
    assert_same(d, d || :b)
  end

  def test_refinement_of_superclass
    assert_separately([], <<~'RUBY')
      module Inactive; refine(Integer) { def &&(other) = :integer }; end
      module Unrelated; refine(String) { def foo = nil }; end
      module Ext; refine(Object) { def &&(other) = :object }; end
      using Unrelated
      using Ext
      3.times do
        assert_equal(:object, 1 && 2)
        assert_equal(:object, "s" && 2)
        assert_equal(:object, nil && 2)
      end
    RUBY
  end

  def test_proc_refined
    assert_separately([], <<~'RUBY')
      Node = Struct.new(:op, :lhs, :rhs)
      module Ext
        refine Node do
          def &&(other) = Node.new(:and, self, other)
          def ||(other) = Node.new(:or, self, other)
        end
      end
      def where(&block) = block.refined(Ext).call
      a, b, c = Node.new(:a), Node.new(:b), Node.new(:c)

      3.times do
        assert_equal(Node.new(:and, a, b), where { a && b })
        assert_equal(Node.new(:or, a, b), where { a || b })
        assert_equal(Node.new(:and, Node.new(:and, a, b), c), where { a && b && c })
        assert_equal(:else, where { nil && b ? :then : :else })
        assert_nil(where { nil && b })
        assert_equal(b, a && b)
        assert_same(a, a || b)
      end
    RUBY
  end
end
