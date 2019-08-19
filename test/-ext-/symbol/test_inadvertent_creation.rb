# frozen_string_literal: false
require 'test/unit'
require_relative 'noninterned_name'

module Test_Symbol
  class TestInadvertent < Test::Unit::TestCase
    include NonInterned

    def setup
      @obj = Object.new
    end

    def assert_not_pinneddown(name, msg = nil)
      assert_not_send([Bug::Symbol, :pinneddown?, name], msg)
    end

    def assert_not_interned(name, msg = nil)
      assert_not_send([Bug::Symbol, :find, name], msg)
    end

    def assert_not_interned_error(obj, meth, name, msg = nil, &block)
      e = assert_raise(NameError, msg) {obj.__send__(meth, name, &block)}
      assert_not_pinneddown(name, msg)
      e
    end

    def assert_not_interned_false(obj, meth, name, msg = nil)
      assert_not_send([obj, meth, name], msg)
      assert_not_pinneddown(name, msg)
    end

    Feature5072 = '[ruby-core:38367]'

    def test_module_const_get
      cl = Class.new
      name = noninterned_name("A")

      assert_not_interned_error(cl, :const_get, name, Feature5072)

      assert_not_interned_error(cl, :const_get, name.to_sym)
    end

    def test_module_const_get_toplevel
      bug12089 = '[ruby-dev:49498] [Bug #12089]'
      name = noninterned_name("A")
      e = assert_not_interned_error(Object, :const_get, name)
      assert_equal(name, e.name)
      assert_not_match(/Object::/, e.message, bug12089)
    end

    def test_module_const_defined?
      cl = Class.new
      name = noninterned_name("A")

      assert_not_interned_false(cl, :const_defined?, name, Feature5072)

      name = noninterned_name
      assert_not_interned_error(cl, :const_defined?, name.to_sym)
    end

    def test_module_define_method_type_error
      cl = Class.new
      name = noninterned_name

      assert_raise(TypeError) {cl.class_eval {define_method(name, "")}}
      assert_not_interned(name)

      assert_raise(TypeError) {cl.class_eval {define_method(name.to_sym, "")}}
      assert_not_pinneddown(name)
    end

    def test_module_define_method_argument_error
      cl = Class.new
      name = noninterned_name

      assert_raise(ArgumentError) {cl.class_eval {define_method(name)}}
      assert_not_interned(name)

      assert_raise(ArgumentError) {cl.class_eval {define_method(name.to_sym)}}
      assert_not_pinneddown(name)
    end

    def test_respond_to_missing
      feature5072 = Feature5072
      c = Class.new do
        def self.respond_to_missing?(*)
          super
        end
      end
      s = noninterned_name

      # assert_not_interned_false(c, :respond_to?, s, feature5072)
      assert_not_interned_false(c, :method_defined?, s, feature5072)
      assert_not_interned_false(c, :public_method_defined?, s, feature5072)
      assert_not_interned_false(c, :private_method_defined?, s, feature5072)
      assert_not_interned_false(c, :protected_method_defined?, s, feature5072)
      assert_not_interned_false(c, :const_defined?, noninterned_name("A"), feature5072)
      assert_not_interned_false(c, :instance_variable_defined?, noninterned_name("@"), feature5072)
      assert_not_interned_false(c, :class_variable_defined?, noninterned_name("@@"), feature5072)
    end

    def test_missing_method
      bug10985 = '[ruby-core:68564] [Bug #10985]'
      m = nil
      c = Class.new do
        def self.respond_to_missing?(*)
          true
        end
      end

      s = noninterned_name
      assert_nothing_raised(NameError, bug10985) {m = c.method(s)}
      assert_raise_with_message(NoMethodError, /#{s}/) {m.call}

      s = noninterned_name
      assert_nothing_raised(NameError, bug10985) {m = c.public_method(s.to_sym)}
      assert_raise_with_message(NoMethodError, /#{s}/) {m.call}

      s = noninterned_name
      assert_nothing_raised(NameError, bug10985) {m = c.singleton_method(s.to_sym)}
      assert_raise_with_message(NoMethodError, /#{s}/) {m.call}
    end

    Feature5079 = '[ruby-core:38404]'

    def test_undefined_instance_variable
      feature5079 = Feature5079
      c = Class.new
      iv = noninterned_name("@")

      assert_not_interned_false(c, :instance_variable_get, iv, feature5079)
      assert_not_interned_error(c, :remove_instance_variable, iv, feature5079)
    end

    def test_undefined_class_variable
      feature5079 = Feature5079
      c = Class.new
      cv = noninterned_name("@@")

      assert_not_interned_error(c, :class_variable_get, cv, feature5079)
      assert_not_interned_error(c, :remove_class_variable, cv, feature5079)
    end


    def test_undefined_const
      feature5079 = Feature5079
      c = Class.new
      s = noninterned_name("A")

      assert_not_interned_error(c, :remove_const, s, feature5079)
    end

    def test_undefined_method
      feature5079 = Feature5079
      c = Class.new
      s = noninterned_name

      assert_not_interned_error(c, :method, s, feature5079)
      assert_not_interned_error(c, :public_method, s, feature5079)
      assert_not_interned_error(c, :instance_method, s, feature5079)
      assert_not_interned_error(c, :public_instance_method, s, feature5079)
      assert_not_interned_error(c, :singleton_method, s, feature5079)
    end

    Feature5089 = '[ruby-core:38447]'
    def test_const_missing
      feature5089 = Feature5089
      c = Class.new do
        def self.const_missing(const_name)
          raise NameError, const_name.to_s
        end
      end
      s = noninterned_name("A")

      assert_not_interned_error(c, :const_get, s.to_sym, feature5089)
      assert_not_interned_false(c, :autoload?, s.to_sym, feature5089)
    end

    def test_aliased_method
      feature5089 = Feature5089
      c = Class.new do
        def self.alias_method(str)
          super(:puts, str)
        end
      end
      s = noninterned_name

      assert_not_interned_error(c, :alias_method, s, feature5089)
      assert_not_interned_error(c, :private_class_method, s, feature5089)
      assert_not_interned_error(c, :private_constant, s, feature5089)
      assert_not_interned_error(c, :private, s, feature5089)
      assert_not_interned_error(c, :protected, s, feature5089)
      assert_not_interned_error(c, :public, s, feature5089)
      assert_not_interned_error(c, :public_class_method, s, feature5089)
      assert_not_interned_error(c, :public_constant, s, feature5089)
      assert_not_interned_error(c, :remove_method, s, feature5089)
      assert_not_interned_error(c, :undef_method, s, feature5089)
      assert_not_interned_error(c, :untrace_var, s, feature5089)
    end

    Feature5112 = '[ruby-core:38576]'

    def test_public_send
      name = noninterned_name
      e = assert_raise(NoMethodError) {@obj.public_send(name, Feature5112)}
      assert_not_interned(name)
      assert_equal(name, e.name)
      assert_equal([Feature5112], e.args)
    end

    def test_send
      name = noninterned_name
      e = assert_raise(NoMethodError) {@obj.send(name, Feature5112)}
      assert_not_interned(name)
      assert_equal(name, e.name)
      assert_equal([Feature5112], e.args)
    end

    def test___send__
      name = noninterned_name
      e = assert_raise(NoMethodError) {@obj.__send__(name, Feature5112)}
      assert_not_interned(name)
      assert_equal(name, e.name)
      assert_equal([Feature5112], e.args)
    end

    def test_thread_aref
      Thread.current[:test] = nil
      name = noninterned_name
      assert_nil(Thread.current[name])
      assert_not_interned(name)
    end

    def test_thread_key?
      Thread.current[:test] = nil
      name = noninterned_name
      assert_not_send([Thread.current, :key?, name])
      assert_not_interned(name)
    end

    def test_thread_variable_get
      Thread.current.thread_variable_set(:test, nil)
      name = noninterned_name
      assert_nil(Thread.current.thread_variable_get(name))
      assert_not_pinneddown(name)
    end

    def test_thread_variable_set
      name = noninterned_name
      Thread.current.thread_variable_set(name, 42)
      assert_not_pinneddown(name)
    end

    def test_thread_variable?
      Thread.current.thread_variable_set(:test, nil)
      name = noninterned_name
      assert_not_send([Thread.current, :thread_variable?, name])
      assert_not_interned(name)
    end

    def test_enumerable_inject_op
      name = noninterned_name
      assert_raise(NoMethodError) {[1, 2].inject(name)}
      assert_not_interned(name)
    end

    def test_module_const_set
      name = noninterned_name
      mod = Module.new
      assert_raise(NameError) {mod.const_set(name, true)}
      assert_not_interned(name)
      assert_raise(NameError) {mod.const_set(name.to_sym, true)}
      assert_not_pinneddown(name)
    end

    def test_module_cvar_set
      name = noninterned_name
      mod = Module.new
      assert_raise(NameError) {mod.class_variable_set(name, true)}
      assert_not_interned(name)
      assert_raise(NameError) {mod.class_variable_set(name.to_sym, true)}
      assert_not_pinneddown(name)
    end

    def test_object_ivar_set
      name = noninterned_name
      obj = Object.new
      assert_raise(NameError) {obj.instance_variable_set(name, true)}
      assert_not_interned(name)
      assert_raise(NameError) {obj.instance_variable_set(name.to_sym, true)}
      assert_not_pinneddown(name)
    end

    def test_struct_new
      name = noninterned_name
      assert_raise(NameError) {Struct.new(name)}
      assert_not_interned(name)
    end

    def test_struct_aref
      s = Struct.new(:foo).new
      name = noninterned_name
      assert_raise(NameError) {s[name]}
      assert_not_interned(name)
    end

    def test_struct_aset
      s = Struct.new(:foo).new
      name = noninterned_name
      assert_raise(NameError) {s[name] = true}
      assert_not_interned(name)
    end

    def test_invalid_attr
      name = noninterned_name("*")
      mod = Module.new
      assert_raise(NameError) {mod.module_eval {attr(name)}}
      assert_not_interned(name)
      assert_raise(NameError) {mod.module_eval {attr(name.to_sym)}}
      assert_not_pinneddown(name)
    end

    def test_invalid_attr_reader
      name = noninterned_name("*")
      mod = Module.new
      assert_raise(NameError) {mod.module_eval {attr_reader(name)}}
      assert_not_interned(name)
      assert_raise(NameError) {mod.module_eval {attr_reader(name.to_sym)}}
      assert_not_pinneddown(name)
    end

    def test_invalid_attr_writer
      name = noninterned_name("*")
      mod = Module.new
      assert_raise(NameError) {mod.module_eval {attr_writer(name)}}
      assert_not_interned(name)
      assert_raise(NameError) {mod.module_eval {attr_writer(name.to_sym)}}
      assert_not_pinneddown(name)
    end

    def test_invalid_attr_accessor
      name = noninterned_name("*")
      mod = Module.new
      assert_raise(NameError) {mod.module_eval {attr_accessor(name)}}
      assert_not_interned(name)
      assert_raise(NameError) {mod.module_eval {attr_accessor(name.to_sym)}}
      assert_not_pinneddown(name)
    end

    def test_gc_attrset
      assert_separately(['-r-test-/symbol', '-r-ext-/symbol/noninterned_name', '-'], "#{<<-'begin;'}\n#{<<-"end;"}")
      bug = '[ruby-core:62226] [Bug #9787]'
      include Test_Symbol::NonInterned
      names = Array.new(1000) {noninterned_name("gc")}
      names.each {|n| n.to_sym}
      GC.start(immediate_sweep: false)
      names.each do |n|
        eval(":#{n}=")
        assert_nothing_raised(TypeError, bug) {eval("proc{self.#{n} = nil}")}
      end
      begin;
      end;
    end

    def test_execopt_key
      name = noninterned_name.intern
      assert_raise(ArgumentError) {
        system(".", name => nil)
      }
      assert_not_pinneddown(name)
    end

    def test_execopt_redirect_value
      name = noninterned_name.intern
      assert_raise(ArgumentError) {
        system(".", [] => name)
      }
      assert_not_pinneddown(name)
    end

    def test_execopt_redirect_path
      name = noninterned_name.intern
      assert_raise(TypeError) {
        system(".", [] => [name, 0])
      }
      assert_not_pinneddown(name)
    end

    def test_execopt_redirect_symbol
      name = noninterned_name.intern
      assert_raise(ArgumentError) {
        system(".", in: name)
      }
      assert_not_pinneddown(name)
    end

    def assert_no_immortal_symbol_created(name)
      name = noninterned_name(name)
      yield(name)
      assert_not_pinneddown(name)
    end

    def assert_no_immortal_symbol_in_method_missing(name)
      assert_no_immortal_symbol_created("send should not leak - #{name}") do |name|
        assert_raise(NoMethodError) {yield(name)}
      end
    end

    def test_send_leak_string
      assert_no_immortal_symbol_in_method_missing("str") do |name|
        42.send(name)
      end
    end

    def test_send_leak_symbol
      assert_no_immortal_symbol_in_method_missing("sym") do |name|
        42.send(name.to_sym)
      end
    end

    def test_send_leak_string_custom_method_missing
      x = Object.new
      def x.method_missing(*); super; end
      assert_no_immortal_symbol_in_method_missing("str mm") do |name|
        x.send(name)
      end
    end

    def test_send_leak_symbol_custom_method_missing
      x = Object.new
      def x.method_missing(*); super; end
      assert_no_immortal_symbol_in_method_missing("sym mm") do |name|
        x.send(name.to_sym)
      end
    end

    def test_send_leak_string_no_optimization
      assert_no_immortal_symbol_in_method_missing("str slow") do |name|
        42.method(:send).call(name)
      end
    end

    def test_send_leak_symbol_no_optimization
      assert_no_immortal_symbol_in_method_missing("sym slow") do |name|
        42.method(:send).call(name.to_sym)
      end
    end

    def test_send_leak_string_custom_method_missing_no_optimization
      x = Object.new
      def x.method_missing(*); super; end
      assert_no_immortal_symbol_in_method_missing("str mm slow") do |name|
        x.method(:send).call(name)
      end
    end

    def test_send_leak_symbol_custom_method_missing_no_optimization
      x = Object.new
      def x.method_missing(*); super; end
      assert_no_immortal_symbol_in_method_missing("sym mm slow") do |name|
        x.method(:send).call(name.to_sym)
      end
    end

    def test_kwarg_symbol_leak_no_rest
      foo = -> (arg: 42) {}
      assert_no_immortal_symbol_created("kwarg no rest") do |name|
        assert_raise(ArgumentError) { foo.call(name.to_sym => 42) }
      end
    end

    def test_kwarg_symbol_leak_with_rest
      foo = -> (arg: 2, **options) {}
      assert_no_immortal_symbol_created("kwarg with rest") do |name|
        foo.call(name.to_sym => 42)
      end
    end

    def test_kwarg_symbol_leak_just_rest
      foo = -> (**options) {}
      assert_no_immortal_symbol_created("kwarg just rest") do |name|
        foo.call(name.to_sym => 42)
      end
    end

    def test_iv_get
      obj = Object.new
      assert_warning(/not initialized/) do
        assert_no_immortal_symbol_created("rb_iv_get") do |name|
          Bug::Symbol.iv_get(obj, name)
        end
      end
    end
  end
end
