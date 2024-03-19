# frozen_string_literal: true

require 'test/unit'

class TestNamespace < Test::Unit::TestCase
  ENV_ENABLE_NAMESPACE = {'RUBY_NAMESPACE' => '1'}

  def setup
    Namespace.enabled = true
    @n = Namespace.new
  end

  def teardown
    Namespace.enabled = nil
  end

  def test_namespace_availability
    Namespace.enabled = nil
    assert !Namespace.enabled
    Namespace.enabled = true
    assert Namespace.enabled
    Namespace.enabled = false
    assert !Namespace.enabled
  end

  def test_current_namespace
    global = Namespace.current
    assert_nil global
    @n.require_relative('namespace/current')
    assert_equal @n, @n::CurrentNamespace.in_require
    assert_equal @n, @n::CurrentNamespace.in_method_call
    assert_nil Namespace.current
  end

  def test_require_rb_separately
    assert_raise(NameError) { NS_A }
    assert_raise(NameError) { NS_B }

    @n.require(File.join(__dir__, 'namespace', 'a.1_1_0'))
    assert_not_nil @n::NS_A
    assert_not_nil @n::NS_B
    assert_equal "1.1.0", @n::NS_A::VERSION
    assert_equal "yay 1.1.0", @n::NS_A.new.yay
    assert_equal "1.1.0", @n::NS_B::VERSION
    assert_equal "yay_b1", @n::NS_B.yay

    assert_raise(NameError) { NS_A }
    assert_raise(NameError) { NS_B }
  end

  def test_require_relative_rb_separately
    assert_raise(NameError) { NS_A }
    assert_raise(NameError) { NS_B }

    @n.require_relative('namespace/a.1_1_0')
    assert_not_nil @n::NS_A
    assert_not_nil @n::NS_B
    assert_equal "1.1.0", @n::NS_A::VERSION
    assert_equal "yay 1.1.0", @n::NS_A.new.yay
    assert_equal "1.1.0", @n::NS_B::VERSION
    assert_equal "yay_b1", @n::NS_B.yay

    assert_raise(NameError) { NS_A }
    assert_raise(NameError) { NS_B }
  end

  def test_load_separately
    assert_raise(NameError) { NS_A } # !
    assert_raise(NameError) { NS_B }

    @n.load(File.join('namespace', 'a.1_1_0.rb'))
    assert_not_nil @n::NS_A
    assert_not_nil @n::NS_B
    assert_equal "1.1.0", @n::NS_A::VERSION
    assert_equal "yay 1.1.0", @n::NS_A.new.yay
    assert_equal "1.1.0", @n::NS_B::VERSION
    assert_equal "yay_b1", @n::NS_B.yay

    assert_raise(NameError) { NS_A }
    assert_raise(NameError) { NS_B }
  end

  def test_namespace_in_namespace
    assert_raise(NameError) { NS1 }
    assert_raise(NameError) { NS_A }
    assert_raise(NameError) { NS_B }

    @n.require_relative('namespace/ns')
    assert_not_nil @n::NS1
    assert_not_nil @n::NS1::NS_A
    assert_not_nil @n::NS1::NS_B
    assert_equal "1.1.0", @n::NS1::NS_A::VERSION
    assert_equal "yay 1.1.0", @n::NS1::NS_A.new.yay
    assert_equal "1.1.0", @n::NS1::NS_B::VERSION
    assert_equal "yay_b1", @n::NS1::NS_B.yay

    assert_raise(NameError) { NS1 }
    assert_raise(NameError) { NS_A }
    assert_raise(NameError) { NS_B }
  end

  def test_require_rb_2versions
    assert_raise(NameError) { NS_A }

    @n.require(File.join(__dir__, 'namespace', 'a.1_2_0'))
    assert_equal "1.2.0", @n::NS_A::VERSION
    assert_equal "yay 1.2.0", @n::NS_A.new.yay

    n2 = Namespace.new
    n2.require(File.join(__dir__, 'namespace', 'a.1_1_0'))
    assert_equal "1.1.0", n2::NS_A::VERSION
    assert_equal "yay 1.1.0", n2::NS_A.new.yay

    # recheck @n is not affected by the following require
    assert_equal "1.2.0", @n::NS_A::VERSION
    assert_equal "yay 1.2.0", @n::NS_A.new.yay

    assert_raise(NameError) { NS_A }
  end

  def test_raising_errors_in_require
    assert_raise(RuntimeError, "Yay!") { @n.require(File.join(__dir__, 'namespace', 'raise')) }
    assert_nil Namespace.current
  end

  def test_autoload_in_namespace
    assert_raise(NameError) { NS_A }

    @n.require_relative('namespace/autoloading')
    # autoloaded A is visible from global
    assert_equal '1.1.0', @n::NS_A::VERSION

    assert_raise(NameError) { NS_A }

    # autoload trigger NS_B::BAR is valid even from global
    assert_equal 'bar_b1', @n::NS_B::BAR

    assert_raise(NameError) { NS_A }
    assert_raise(NameError) { NS_B }
  end

  def test_continuous_top_level_method_in_a_namespace
    @n.require_relative('namespace/define_toplevel')
    @n.require_relative('namespace/call_toplevel')
    assert_raise(NameError) { foo }
  end

  def test_top_level_methods_in_namespace
    @n.require_relative('namespace/top_level')
    assert_equal "yay!", @n::Foo.foo
    assert_raise(NameError) { yaaay }
    assert_equal "foo", @n::Bar.bar
    assert_raise_with_message(RuntimeError, "boooo") { @n::Baz.baz }
  end

  def test_proc_defined_in_namespace_refers_module_in_namespace
    # require_relative dosn't work well in assert_separately even with __FILE__ and __LINE__
    assert_separately([ENV_ENABLE_NAMESPACE], __FILE__, __LINE__, "here = '#{__dir__}'; #{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      ns1 = Namespace.new
      ns1.require(File.join("#{here}", 'namespace/proc_callee'))
      proc_v = ns1::Foo.callee
      assert_raise(NameError) { Target }
      assert ns1::Target
      assert_equal "fooooo", proc_v.call # refers Target in the namespace ns1
      ns1.require(File.join("#{here}", 'namespace/proc_caller'))
      assert_equal "fooooo", ns1::Bar.caller(proc_v)

      ns2 = Namespace.new
      ns2.require(File.join("#{here}", 'namespace/proc_caller'))
      assert_raise(NameError) { ns2::Target }
      assert_equal "fooooo", ns2::Bar.caller(proc_v) # refers Target in the namespace ns1
    end;
  end

  def test_proc_defined_globally_refers_global_module
    # require_relative dosn't work well in assert_separately even with __FILE__ and __LINE__
    assert_separately([ENV_ENABLE_NAMESPACE], __FILE__, __LINE__, "here = '#{__dir__}'; #{<<~"begin;"}\n#{<<~'end;'}", ignore_stderr: true)
    begin;
      require(File.join("#{here}", 'namespace/proc_callee'))
      def Target.foo
        "yay"
      end
      proc_v = Foo.callee
      assert Target
      assert_equal "yay", proc_v.call # refers global Foo
      ns1 = Namespace.new
      ns1.require(File.join("#{here}", 'namespace/proc_caller'))
      assert_equal "yay", ns1::Bar.caller(proc_v)

      ns2 = Namespace.new
      ns2.require(File.join("#{here}", 'namespace/proc_callee'))
      ns2.require(File.join("#{here}", 'namespace/proc_caller'))
      assert_equal "fooooo", ns2::Foo.callee.call
      assert_equal "yay", ns2::Bar.caller(proc_v) # should refer the global Target, not Foo in ns2
    end;
  end
end

class NSDummyBuiltinA; def foo; "a"; end; end
module NSDummyBuiltinB; def foo; "b"; end; end
Namespace.force_builtin(NSDummyBuiltinA)
Namespace.force_builtin(NSDummyBuiltinB)

class NSUsualClassC; def foo; "a"; end; end
module NSUsualModuleD; def foo; "b"; end; end

class TestNamespace < Test::Unit::TestCase
  def test_builtin_classes_and_modules_are_reopened
    @n.require_relative('namespace/reopen_classes_modules')

    assert_equal "A", @n::NSReopenClassesModules.test_a
    assert_raise(NameError){ @n::NSDummyBuiltinA }
    assert_equal "B", @n::NSReopenClassesModules.test_b
    assert_raise(NameError){ @n::NSDummyBuiltinB }

    assert_raise(NameError){ @n::NSReopenClassesModules.test_c }
    assert_not_nil @n::NSUsualClassC
    assert_raise(NameError){ @n::NSReopenClassesModules.test_d }
    assert_not_nil @n::NSUsualModuleD
  end

  def test_methods_added_in_namespace_are_invisible_globally
    @n.require_relative('namespace/string_ext')
    assert_equal "yay", @n::Bar.yay

    assert_raise(NoMethodError){ String.new.yay }
  end

  def test_continuous_method_definitions_in_a_namespace
    @n.require_relative('namespace/string_ext')
    assert_equal "yay", @n::Bar.yay

    @n.require_relative('namespace/string_ext_caller')
    assert_equal "yay", @n::Foo.yay

    @n.require_relative('namespace/string_ext_calling')
  end

  def test_methods_added_in_namespace_later_than_caller_code
    @n.require_relative('namespace/string_ext_caller')

    @n.require_relative('namespace/string_ext')
    assert_equal "yay", @n::Bar.yay

    pend # TODO: The file (ISeq) required previously cannot be refined correctly by the following file (and its refinement)
    assert_equal "yay", @n::Foo.yay #TODO: NoMethodError
  end

  def test_method_added_in_namespace_are_available_on_eval
    @n.require_relative('namespace/string_ext')

    @n.require_relative('namespace/string_ext_eval_caller')
    assert_equal "yay", @n::Baz.yay
  end

  def test_method_added_in_namespace_are_available_on_eval_with_binding
    @n.require_relative('namespace/string_ext')

    @n.require_relative('namespace/string_ext_eval_caller')
    assert_equal "yay, yay!", @n::Baz.yay_with_binding
  end
end

module ProcLookupTestA
  module B
    VALUE = 111
  end
end

class TestNamespace < Test::Unit::TestCase
  def make_proc_from_block(&b)
    b
  end

  def test_proc_from_global_works_with_global_definitions
    @n.require_relative('namespace/procs')

    str_pr1 = Proc.new { String.new.yay }
    str_pr2 = proc { String.new.yay }
    str_pr3 = lambda { String.new.yay }
    str_pr4 = ->(){ String.new.yay }
    str_pr5 = make_proc_from_block { String.new.yay }
    str_pr6 = @n::ProcInNS.make_proc_from_block { String.new.yay }

    assert_raise(NoMethodError) { str_pr1.call }
    assert_raise(NoMethodError) { str_pr2.call }
    assert_raise(NoMethodError) { str_pr3.call }
    assert_raise(NoMethodError) { str_pr4.call }
    assert_raise(NoMethodError) { str_pr5.call }
    assert_raise(NoMethodError) { str_pr6.call }

    assert_raise(NoMethodError) { @n::ProcInNS.call_proc(str_pr1) }
    assert_raise(NoMethodError) { @n::ProcInNS.call_proc(str_pr2) }
    assert_raise(NoMethodError) { @n::ProcInNS.call_proc(str_pr3) }
    assert_raise(NoMethodError) { @n::ProcInNS.call_proc(str_pr4) }
    assert_raise(NoMethodError) { @n::ProcInNS.call_proc(str_pr5) }
    assert_raise(NoMethodError) { @n::ProcInNS.call_proc(str_pr6) }

    const_pr1 = Proc.new { ProcLookupTestA::B::VALUE }
    const_pr2 = proc { ProcLookupTestA::B::VALUE }
    const_pr3 = lambda { ProcLookupTestA::B::VALUE }
    const_pr4 = ->(){ ProcLookupTestA::B::VALUE }
    const_pr5 = make_proc_from_block { ProcLookupTestA::B::VALUE }
    const_pr6 = @n::ProcInNS.make_proc_from_block { ProcLookupTestA::B::VALUE }

    assert_equal 111, @n::ProcInNS.call_proc(const_pr1)
    assert_equal 111, @n::ProcInNS.call_proc(const_pr2)
    assert_equal 111, @n::ProcInNS.call_proc(const_pr3)
    assert_equal 111, @n::ProcInNS.call_proc(const_pr4)
    assert_equal 111, @n::ProcInNS.call_proc(const_pr5)
    assert_equal 111, @n::ProcInNS.call_proc(const_pr6)
  end

  def test_proc_from_namespace_works_with_definitions_in_namespace
    @n.require_relative('namespace/procs')

    str_pr1 = @n::ProcInNS.make_str_proc(:proc_new)
    str_pr2 = @n::ProcInNS.make_str_proc(:proc_f)
    str_pr3 = @n::ProcInNS.make_str_proc(:lambda_f)
    str_pr4 = @n::ProcInNS.make_str_proc(:lambda_l)
    str_pr5 = @n::ProcInNS.make_str_proc(:block)

    assert_equal "yay", str_pr1.call
    assert_equal "yay", str_pr2.call
    assert_equal "yay", str_pr3.call
    assert_equal "yay", str_pr4.call
    assert_equal "yay", str_pr5.call

    const_pr1 = @n::ProcInNS.make_const_proc(:proc_new)
    const_pr2 = @n::ProcInNS.make_const_proc(:proc_f)
    const_pr3 = @n::ProcInNS.make_const_proc(:lambda_f)
    const_pr4 = @n::ProcInNS.make_const_proc(:lambda_l)
    const_pr5 = @n::ProcInNS.make_const_proc(:block)

    assert_equal 222, const_pr1.call
    assert_equal 222, const_pr2.call
    assert_equal 222, const_pr3.call
    assert_equal 222, const_pr4.call
    assert_equal 222, const_pr5.call

    str_const_pr1 = @n::ProcInNS.make_str_const_proc(:proc_new)
    str_const_pr2 = @n::ProcInNS.make_str_const_proc(:proc_f)
    str_const_pr3 = @n::ProcInNS.make_str_const_proc(:lambda_f)
    str_const_pr4 = @n::ProcInNS.make_str_const_proc(:lambda_l)
    str_const_pr5 = @n::ProcInNS.make_str_const_proc(:block)

    assert_equal "yay,foo,222", @n::ProcInNS::CONST_PROC_NEW.call
    assert_equal "yay,foo,222", @n::ProcInNS::CONST_PROC_F.call
    assert_equal "yay,foo,222", @n::ProcInNS::CONST_LAMBDA_F.call
    assert_equal "yay,foo,222", @n::ProcInNS::CONST_LAMBDA_L.call
    assert_equal "yay,foo,222", @n::ProcInNS::CONST_BLOCK.call
  end
end

class NSBuiltinSMethodsC
  def self.create
    self.new
  end

  def self.prefix
    "c-"
  end
end
module NSBuiltinSMethodsM
  def self.prefix
    "m-"
  end
end
Namespace.force_builtin(NSBuiltinSMethodsC)
Namespace.force_builtin(NSBuiltinSMethodsM)

class TestNamespace < Test::Unit::TestCase
  def test_class_module_singleton_methods
    @n.require_relative('namespace/singleton_methods')

    pend
    assert_equal "c-yay-c", @n::SingletonMethods.class_def_with_self
    assert_equal "c-foo-c", @n::SingletonMethods.class_open_self
    assert_equal "m-yay-m", @n::SingletonMethods.module_def_with_self
    assert_equal "m-foo-m", @n::SingletonMethods.module_open_self
  end

  def test_add_constants_in_namespace
    String.const_set(:STR_CONST0, 999)
    assert_equal 999, String::STR_CONST0
    assert_equal 999, String.const_get(:STR_CONST0)

    assert_raise(NameError) { String.const_get(:STR_CONST1) }
    assert_raise(NameError) { String::STR_CONST2 }
    assert_raise(NameError) { String::STR_CONST3 }
    assert_raise(NameError) { Integer.const_get(:INT_CONST1) }

    EnvUtil.suppress_warning do
      @n.require_relative('namespace/consts')
    end
    assert_equal 999, String::STR_CONST0
    assert_raise(NameError) { String::STR_CONST1 }
    assert_raise(NameError) { String::STR_CONST2 }
    assert_raise(NameError) { Integer::INT_CONST1 }

    assert_not_nil @n::ForConsts.refer_all

    # TODO: support #remove_const in namespaces
    # assert_raise(NameError) { @n::ForConsts.refer0 }
    # assert_raise(NameError) { @n::ForConsts.get0 }

    assert_equal 112, @n::ForConsts.refer1
    assert_equal 112, @n::ForConsts.get1
    assert_equal 112, @n::ForConsts::CONST1
    assert_equal 222, @n::ForConsts.refer2
    assert_equal 222, @n::ForConsts.get2
    assert_equal 222, @n::ForConsts::CONST2
    assert_equal 333, @n::ForConsts.refer3
    assert_equal 333, @n::ForConsts.get3
    assert_equal 333, @n::ForConsts::CONST3

    EnvUtil.suppress_warning do
      @n::ForConsts.const_set(:CONST3, 334)
    end
    assert_equal 334, @n::ForConsts::CONST3
    assert_equal 334, @n::ForConsts.refer3
    assert_equal 334, @n::ForConsts.get3

    assert_equal 10, @n::ForConsts.refer_top_const

    # use Proxy object to use usual methods instead of singleton methods
    proxy = @n::ForConsts::Proxy.new
    assert_equal 112, proxy.call_str_refer1
    assert_equal 112, proxy.call_str_get1
    assert_equal 223, proxy.call_str_refer2
    assert_equal 223, proxy.call_str_get2
    assert_equal 333, proxy.call_str_refer3
    assert_equal 333, proxy.call_str_get3

    EnvUtil.suppress_warning do
      proxy.call_str_set3
    end
    assert_equal 334, proxy.call_str_refer3
    assert_equal 334, proxy.call_str_get3

    assert_equal 1, proxy.refer_int_const1

    assert_equal 999, String::STR_CONST0
    assert_raise(NameError) { String::STR_CONST1 }
    assert_raise(NameError) { String::STR_CONST2 }
    assert_raise(NameError) { String::STR_CONST3 }
    assert_raise(NameError) { Integer::INT_CONST1 }
  end

  def test_global_variables
    default_l = $-0
    default_f = $,

    assert_equal "\n", $-0 # equal to $/, line splitter
    assert_equal nil, $,   # field splitter

    @n.require_relative('namespace/global_vars')

    # read first
    assert_equal "\n", @n::LineSplitter.read
    @n::LineSplitter.write("\r\n")
    assert_equal "\r\n", @n::LineSplitter.read
    assert_equal "\n", $-0

    # write first
    @n::FieldSplitter.write(",")
    assert_equal ",", @n::FieldSplitter.read
    assert_equal nil, $,

    # used only in ns
    assert !global_variables.include?(:$used_only_in_ns)
    @n::UniqueGvar.write(123)
    assert_equal 123, @n::UniqueGvar.read
    assert_nil $used_only_in_ns

    # Kernel#global_variables returns the sum of all gvars.
    global_gvars = global_variables.sort
    assert_equal global_gvars, @n::UniqueGvar.gvars_in_ns.sort
    @n::UniqueGvar.write_only(456)
    assert_equal (global_gvars + [:$write_only_var_in_ns]).sort, @n::UniqueGvar.gvars_in_ns.sort
    assert_equal (global_gvars + [:$write_only_var_in_ns]).sort, global_variables.sort
  ensure
    EnvUtil.suppress_warning do
      $-0 = default_l
      $, = default_f
    end
  end
end
