# frozen_string_literal: false
require 'test/unit'

class TestVariable < Test::Unit::TestCase
  class Gods
    @@rule = "Uranus"
    def ruler0
      @@rule
    end

    def self.ruler1		# <= per method definition style
      @@rule
    end
    class << self			# <= multiple method definition style
      def ruler2
	@@rule
      end
    end
  end

  module Olympians
    @@rule ="Zeus"
    def ruler3
      @@rule
    end
  end

  class Titans < Gods
    @@rule = "Cronus"			# modifies @@rule in Gods
    include Olympians
    def ruler4
      @@rule
    end
  end

  Athena = Gods.clone

  def test_cloned_classes_copy_cvar_cache
    assert_equal "Cronus", Athena.new.ruler0
  end

  def test_setting_class_variable_on_module_through_inheritance
    mod = Module.new
    mod.class_variable_set(:@@foo, 1)
    mod.freeze
    c = Class.new { include(mod) }
    assert_raise(FrozenError) { c.class_variable_set(:@@foo, 2) }
    assert_raise(FrozenError) { c.class_eval("@@foo = 2") }
    assert_equal(1, c.class_variable_get(:@@foo))
  end

  Zeus = Gods.clone

  def test_cloned_allows_setting_cvar
    Zeus.class_variable_set(:@@rule, "Athena")

    god = Gods.new.ruler0
    zeus = Zeus.new.ruler0

    assert_equal "Cronus", god
    assert_equal "Athena", zeus
    assert_not_equal god.object_id, zeus.object_id
  end

  def test_singleton_class_included_class_variable
    c = Class.new
    c.extend(Olympians)
    assert_empty(c.singleton_class.class_variables)
    assert_raise(NameError){ c.singleton_class.class_variable_get(:@@rule) }
    c.class_variable_set(:@@foo, 1)
    assert_equal([:@@foo], c.singleton_class.class_variables)
    assert_equal(1, c.singleton_class.class_variable_get(:@@foo))

    c = Class.new
    c.extend(Olympians)
    sc = Class.new(c)
    assert_empty(sc.singleton_class.class_variables)
    assert_raise(NameError){ sc.singleton_class.class_variable_get(:@@rule) }
    c.class_variable_set(:@@foo, 1)
    assert_equal([:@@foo], sc.singleton_class.class_variables)
    assert_equal(1, sc.singleton_class.class_variable_get(:@@foo))

    c = Class.new
    o = c.new
    o.extend(Olympians)
    assert_equal([:@@rule], o.singleton_class.class_variables)
    assert_equal("Zeus", o.singleton_class.class_variable_get(:@@rule))
    c.class_variable_set(:@@foo, 1)
    assert_equal([:@@foo, :@@rule], o.singleton_class.class_variables.sort)
    assert_equal(1, o.singleton_class.class_variable_get(:@@foo))
  end

  def test_cvar_overtaken_by_parent_class
    error = eval <<~EORB
      class Parent
      end

      class Child < Parent
        @@cvar = 1

        def self.cvar
          @@cvar
        end
      end

      assert_equal 1, Child.cvar

      class Parent
        @@cvar = 2
      end

      assert_raise RuntimeError do
        Child.cvar
      end
    EORB

    assert_equal "class variable @@cvar of TestVariable::Child is overtaken by TestVariable::Parent", error.message
  ensure
    TestVariable.send(:remove_const, :Child) rescue nil
    TestVariable.send(:remove_const, :Parent) rescue nil
  end

  def test_cvar_overtaken_by_module
    error = eval <<~EORB
      class ParentForModule
        @@cvar = 1

        def self.cvar
          @@cvar
        end
      end

      assert_equal 1, ParentForModule.cvar

      module Mixin
        @@cvar = 2
      end

      class ParentForModule
        include Mixin
      end

      assert_raise RuntimeError do
        ParentForModule.cvar
      end
    EORB

    assert_equal "class variable @@cvar of TestVariable::ParentForModule is overtaken by TestVariable::Mixin", error.message
  ensure
    TestVariable.send(:remove_const, :Mixin) rescue nil
    TestVariable.send(:remove_const, :ParentForModule) rescue nil
  end

  class IncludeRefinedModuleClassVariableNoWarning
    module Mod
      @@_test_include_refined_module_class_variable = true
    end

    module Mod2
      refine Mod do
      end
    end

    include Mod

    def t
      @@_test_include_refined_module_class_variable
    end
  end

  def test_include_refined_module_class_variable
    assert_warning('') do
      IncludeRefinedModuleClassVariableNoWarning.new.t
    end
  end

  def test_set_class_variable_on_frozen_object
    set_cvar = EnvUtil.labeled_class("SetCVar")
    set_cvar.class_eval "#{<<~"begin;"}\n#{<<~'end;'}"
    begin;
      def self.set(val)
        @@a = val # inline cache
      end
    end;
    set_cvar.set(1) # fill write cache
    set_cvar.freeze
    assert_raise(FrozenError, "[Bug #19341]") do
      set_cvar.set(2) # hit write cache, but should check frozen status
    end
  end

  def test_variable
    assert_instance_of(Integer, $$)

    # read-only variable
    assert_raise(NameError) do
      $$ = 5
    end
    assert_normal_exit("$*=0; $*", "[ruby-dev:36698]")

    foobar = "foobar"
    $_ = foobar
    assert_equal(foobar, $_)

    assert_equal("Cronus", Gods.new.ruler0)
    assert_equal("Cronus", Gods.ruler1)
    assert_equal("Cronus", Gods.ruler2)
    assert_equal("Cronus", Titans.ruler1)
    assert_equal("Cronus", Titans.ruler2)
    atlas = Titans.new
    assert_equal("Cronus", atlas.ruler0)
    assert_equal("Zeus", atlas.ruler3)
    assert_raise(RuntimeError) { atlas.ruler4 }
    assert_nothing_raised do
      class << Gods
        defined?(@@rule) && @@rule
      end
    end
  end

  def test_local_variables
    lvar = 1
    assert_instance_of(Symbol, local_variables[0], "[ruby-dev:34008]")
    lvar
  end

  def test_local_variables2
    x = 1
    proc do |y|
      assert_equal([:x, :y], local_variables.sort)
    end.call
    x
  end

  def test_local_variables3
    x = 1
    proc do |y|
      1.times do |z|
        assert_equal([:x, :y, :z], local_variables.sort)
      end
    end.call
    x
  end

  def test_shadowing_local_variables
    bug9486 = '[ruby-core:60501] [Bug #9486]'
    assert_equal([:x, :bug9486], tap {|x| break local_variables}, bug9486)
  end

  def test_shadowing_block_local_variables
    bug9486 = '[ruby-core:60501] [Bug #9486]'
    assert_equal([:x, :bug9486], tap {|;x| x = x; break local_variables}, bug9486)
  end

  def test_global_variables
    gv = global_variables
    assert_empty(gv.grep(/\A(?!\$)/))
    assert_nil($~)
    assert_not_include(gv, :$1)
    /(\w)(\d)?(.)(.)(.)(.)(.)(.)(.)(.)(\d)?(.)/ =~ "globalglobalglobal"
    assert_not_nil($~)
    gv = global_variables - gv
    assert_include(gv, :$1)
    assert_not_include(gv, :$2)
    assert_not_include(gv, :$11)
    assert_include(gv, :$12)
  end

  def prepare_klass_for_test_svar_with_ifunc
    Class.new do
      include Enumerable
      def each(&b)
        @b = b
      end

      def check1
        check2.merge({check1: $1})
      end

      def check2
        @b.call('foo')
        {check2: $1}
      end
    end
  end

  def test_svar_with_ifunc
    c = prepare_klass_for_test_svar_with_ifunc

    expected_check1_result = {
      check1: nil, check2: nil
    }.freeze

    obj = c.new
    result = nil
    obj.grep(/(f..)/){
      result = $1
    }
    assert_equal nil, result
    assert_equal nil, $1
    assert_equal expected_check1_result, obj.check1
    assert_equal 'foo', result
    assert_equal 'foo', $1

    # this frame was escaped so try it again
    $~ = nil
    obj = c.new
    result = nil
    obj.grep(/(f..)/){
      result = $1
    }
    assert_equal nil, result
    assert_equal nil, $1
    assert_equal expected_check1_result, obj.check1
    assert_equal 'foo', result
    assert_equal 'foo', $1

    # different context
    result = nil
    Fiber.new{
      obj = c.new
      obj.grep(/(f..)/){
        result = $1
      }
    }.resume # obj is created in antoher Fiber
    assert_equal nil, result
    assert_equal expected_check1_result, obj.check1
    assert_equal 'foo', result
    assert_equal 'foo', $1

    # different thread context
    result = nil
    Thread.new{
      obj = c.new
      obj.grep(/(f..)/){
        result = $1
      }
    }.join # obj is created in another Thread

    assert_equal nil, result
    assert_equal expected_check1_result, obj.check1
    assert_equal 'foo', result
    assert_equal 'foo', $1
  end


  def test_global_variable_0
    assert_in_out_err(["-e", "$0='t'*1000;print $0"], "", /\At+\z/, [])
  end

  def test_global_variable_popped
    assert_nothing_raised {
      EnvUtil.suppress_warning {
        eval("$foo; 1")
      }
    }
  end

  def test_constant_popped
    assert_nothing_raised {
      EnvUtil.suppress_warning {
        eval("TestVariable::Gods; 1")
      }
    }
  end

  def test_special_constant_ivars
    [ true, false, :symbol, "dsym#{rand(9999)}".to_sym, 1, 1.0 ].each do |v|
      assert_empty v.instance_variables
      msg = "can't modify frozen #{v.class}: #{v.inspect}"

      assert_raise_with_message(FrozenError, msg) do
        v.instance_variable_set(:@foo, :bar)
      end

      assert_raise_with_message(FrozenError, msg, "[Bug #19339]") do
        v.instance_eval do
          @a = 1
        end
      end

      assert_nil EnvUtil.suppress_warning {v.instance_variable_get(:@foo)}
      assert_not_send([v, :instance_variable_defined?, :@foo])

      assert_raise_with_message(FrozenError, msg) do
        v.remove_instance_variable(:@foo)
      end
    end
  end

  class ExIvar < Hash
    def initialize
      @a = 1
      @b = 2
      @c = 3
    end

    def ivars
      [@a, @b, @c]
    end
  end

  def test_external_ivars
    3.times{
      # check inline cache for external ivar access
      assert_equal [1, 2, 3], ExIvar.new.ivars
    }
  end

  def test_local_variables_with_kwarg
    bug11674 = '[ruby-core:71437] [Bug #11674]'
    v = with_kwargs_11(v1:1,v2:2,v3:3,v4:4,v5:5,v6:6,v7:7,v8:8,v9:9,v10:10,v11:11)
    assert_equal(%i(v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11), v, bug11674)
  end

  def test_many_instance_variables
    objects = [Object.new, Hash.new, Module.new]
    objects.each do |obj|
      1000.times do |i|
        obj.instance_variable_set("@var#{i}", i)
      end
      1000.times do |i|
        assert_equal(i, obj.instance_variable_get("@var#{i}"))
      end
    end
  end

  def test_local_variables_encoding
    α = 1
    b = binding
    b.eval("".encode("us-ascii"))
    assert_equal(%i[α b], b.local_variables)
  end

  private
  def with_kwargs_11(v1:, v2:, v3:, v4:, v5:, v6:, v7:, v8:, v9:, v10:, v11:)
    local_variables
  end
end
