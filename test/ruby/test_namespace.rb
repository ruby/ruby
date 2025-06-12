# frozen_string_literal: true

require 'test/unit'

class TestNamespace < Test::Unit::TestCase
  ENV_ENABLE_NAMESPACE = {'RUBY_NAMESPACE' => '1'}

  def setup
    @n = Namespace.new if Namespace.enabled?
  end

  def teardown
    @n = nil
  end

  def test_namespace_availability
    env_has_RUBY_NAMESPACE = (ENV['RUBY_NAMESPACE'].to_i == 1)
    assert_equal env_has_RUBY_NAMESPACE, Namespace.enabled?
  end

  def test_current_namespace
    pend unless Namespace.enabled?

    main = Namespace.current
    assert main.inspect.include?("main")

    @n.require_relative('namespace/current')

    assert_equal @n, @n::CurrentNamespace.in_require
    assert_equal @n, @n::CurrentNamespace.in_method_call
    assert_equal main, Namespace.current
  end

  def test_require_rb_separately
    pend unless Namespace.enabled?

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
    pend unless Namespace.enabled?

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
    pend unless Namespace.enabled?

    assert_raise(NameError) { NS_A }
    assert_raise(NameError) { NS_B }

    @n.load(File.join(__dir__, 'namespace', 'a.1_1_0.rb'))

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
    pend unless Namespace.enabled?

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
    pend unless Namespace.enabled?

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
    pend unless Namespace.enabled?

    assert_raise(RuntimeError, "Yay!") { @n.require(File.join(__dir__, 'namespace', 'raise')) }
    assert Namespace.current.inspect.include?("main")
  end

  def test_autoload_in_namespace
    pend unless Namespace.enabled?

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
    pend unless Namespace.enabled?

    @n.require_relative('namespace/define_toplevel')
    @n.require_relative('namespace/call_toplevel')

    assert_raise(NameError) { foo }
  end

  def test_top_level_methods_in_namespace
    pend # TODO: fix loading/current namespace detection
    pend unless Namespace.enabled?
    @n.require_relative('namespace/top_level')
    assert_equal "yay!", @n::Foo.foo
    assert_raise(NameError) { yaaay }
    assert_equal "foo", @n::Bar.bar
    assert_raise_with_message(RuntimeError, "boooo") { @n::Baz.baz }
  end

  def test_proc_defined_in_namespace_refers_module_in_namespace
    pend unless Namespace.enabled?

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
    pend unless Namespace.enabled?

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

  def test_instance_variable
    pend unless Namespace.enabled?

    @n.require_relative('namespace/instance_variables')

    assert_equal [], String.instance_variables
    assert_equal [:@str_ivar1, :@str_ivar2], @n::StringDelegatorObj.instance_variables
    assert_equal 111, @n::StringDelegatorObj.str_ivar1
    assert_equal 222, @n::StringDelegatorObj.str_ivar2
    assert_equal 222, @n::StringDelegatorObj.instance_variable_get(:@str_ivar2)

    @n::StringDelegatorObj.instance_variable_set(:@str_ivar3, 333)
    assert_equal 333, @n::StringDelegatorObj.instance_variable_get(:@str_ivar3)
    @n::StringDelegatorObj.remove_instance_variable(:@str_ivar1)
    assert_nil @n::StringDelegatorObj.str_ivar1
    assert_equal [:@str_ivar2, :@str_ivar3], @n::StringDelegatorObj.instance_variables

    assert_equal [], String.instance_variables
  end

  def test_methods_added_in_namespace_are_invisible_globally
    pend unless Namespace.enabled?

    @n.require_relative('namespace/string_ext')

    assert_equal "yay", @n::Bar.yay

    assert_raise(NoMethodError){ String.new.yay }
  end

  def test_continuous_method_definitions_in_a_namespace
    pend unless Namespace.enabled?

    @n.require_relative('namespace/string_ext')
    assert_equal "yay", @n::Bar.yay

    @n.require_relative('namespace/string_ext_caller')
    assert_equal "yay", @n::Foo.yay

    @n.require_relative('namespace/string_ext_calling')
  end

  def test_methods_added_in_namespace_later_than_caller_code
    pend unless Namespace.enabled?

    @n.require_relative('namespace/string_ext_caller')
    @n.require_relative('namespace/string_ext')

    assert_equal "yay", @n::Bar.yay
    assert_equal "yay", @n::Foo.yay
  end

  def test_method_added_in_namespace_are_available_on_eval
    pend unless Namespace.enabled?

    @n.require_relative('namespace/string_ext')
    @n.require_relative('namespace/string_ext_eval_caller')

    assert_equal "yay", @n::Baz.yay
  end

  def test_method_added_in_namespace_are_available_on_eval_with_binding
    pend unless Namespace.enabled?

    @n.require_relative('namespace/string_ext')
    @n.require_relative('namespace/string_ext_eval_caller')

    assert_equal "yay, yay!", @n::Baz.yay_with_binding
  end

  def test_methods_and_constants_added_by_include
    pend unless Namespace.enabled?

    @n.require_relative('namespace/open_class_with_include')

    assert_equal "I'm saying foo 1", @n::OpenClassWithInclude.say
    assert_equal "I'm saying foo 1", @n::OpenClassWithInclude.say_foo
    assert_equal "I'm saying foo 1", @n::OpenClassWithInclude.say_with_obj("wow")

    assert_raise(NameError) { String::FOO }

    assert_equal "foo 1", @n::OpenClassWithInclude.refer_foo
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

  def test_proc_from_main_works_with_global_definitions
    pend unless Namespace.enabled?

    @n.require_relative('namespace/procs')

    proc_and_labels = [
      [Proc.new { String.new.yay }, "Proc.new"],
      [proc { String.new.yay }, "proc{}"],
      [lambda { String.new.yay }, "lambda{}"],
      [->(){ String.new.yay }, "->(){}"],
      [make_proc_from_block { String.new.yay }, "make_proc_from_block"],
      [@n::ProcInNS.make_proc_from_block { String.new.yay }, "make_proc_from_block in @n"],
    ]

    proc_and_labels.each do |str_pr|
      pr, pr_label = str_pr
      assert_raise(NoMethodError, "NoMethodError expected: #{pr_label}, called in main") { pr.call }
      assert_raise(NoMethodError, "NoMethodError expected: #{pr_label}, called in @n") { @n::ProcInNS.call_proc(pr) }
    end

    const_and_labels = [
      [Proc.new { ProcLookupTestA::B::VALUE }, "Proc.new"],
      [proc { ProcLookupTestA::B::VALUE }, "proc{}"],
      [lambda { ProcLookupTestA::B::VALUE }, "lambda{}"],
      [->(){ ProcLookupTestA::B::VALUE }, "->(){}"],
      [make_proc_from_block { ProcLookupTestA::B::VALUE }, "make_proc_from_block"],
      [@n::ProcInNS.make_proc_from_block { ProcLookupTestA::B::VALUE }, "make_proc_from_block in @n"],
    ]

    const_and_labels.each do |const_pr|
      pr, pr_label = const_pr
      assert_equal 111, pr.call, "111 expected, #{pr_label} called in main"
      assert_equal 111, @n::ProcInNS.call_proc(pr), "111 expected, #{pr_label} called in @n"
    end
  end

  def test_proc_from_namespace_works_with_definitions_in_namespace
    pend unless Namespace.enabled?

    @n.require_relative('namespace/procs')

    proc_types = [:proc_new, :proc_f, :lambda_f, :lambda_l, :block]

    proc_types.each do |proc_type|
      assert_equal 222, @n::ProcInNS.make_const_proc(proc_type).call, "ProcLookupTestA::B::VALUE should be 222 in @n"
      assert_equal "foo", @n::ProcInNS.make_str_const_proc(proc_type).call, "String::FOO should be \"foo\" in @n"
      assert_equal "yay", @n::ProcInNS.make_str_proc(proc_type).call, "String#yay should be callable in @n"
      #
      # TODO: method calls not-in-methods nor procs can't handle the current namespace correctly.
      #
      # assert_equal "yay,foo,222",
      #              @n::ProcInNS.const_get(('CONST_' + proc_type.to_s.upcase).to_sym).call,
      #              "Proc assigned to constants should refer constants correctly in @n"
    end
  end

  def test_class_module_singleton_methods
    pend unless Namespace.enabled?

    @n.require_relative('namespace/singleton_methods')

    assert_equal "Good evening!", @n::SingletonMethods.string_greeing # def self.greeting
    assert_equal 42, @n::SingletonMethods.integer_answer # class << self; def answer
    assert_equal([], @n::SingletonMethods.array_blank) # def self.blank w/ instance methods
    assert_equal({status: 200, body: 'OK'}, @n::SingletonMethods.hash_http_200) # class << self; def ... w/ instance methods

    assert_equal([4, 4], @n::SingletonMethods.array_instance_methods_return_size([1, 2, 3, 4]))
    assert_equal([3, 3], @n::SingletonMethods.hash_instance_methods_return_size({a: 2, b: 4, c: 8}))

    assert_raise(NoMethodError) { String.greeting }
    assert_raise(NoMethodError) { Integer.answer }
    assert_raise(NoMethodError) { Array.blank }
    assert_raise(NoMethodError) { Hash.http_200 }
  end

  def test_add_constants_in_namespace
    pend unless Namespace.enabled?

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

    assert_raise(NameError){ proxy.call_str_refer0 }
    assert_raise(NameError){ proxy.call_str_get0 }

    proxy.call_str_set0(30)
    assert_equal 30, proxy.call_str_refer0
    assert_equal 30, proxy.call_str_get0
    assert_equal 999, String::STR_CONST0

    proxy.call_str_remove0
    assert_raise(NameError){ proxy.call_str_refer0 }
    assert_raise(NameError){ proxy.call_str_get0 }

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

    pend unless Namespace.enabled?

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

  def test_load_path_and_loaded_features
    pend unless Namespace.enabled?

    assert $LOAD_PATH.respond_to?(:resolve_feature_path)

    @n.require_relative('namespace/load_path')

    assert_not_equal $LOAD_PATH, @n::LoadPathCheck::FIRST_LOAD_PATH

    assert @n::LoadPathCheck::FIRST_LOAD_PATH_RESPOND_TO_RESOLVE

    namespace_dir = File.join(__dir__, 'namespace')
    # TODO: $LOADED_FEATURES in method calls should refer the current namespace in addition to the loading namespace.
    # assert @n::LoadPathCheck.current_loaded_features.include?(File.join(namespace_dir, 'blank1.rb'))
    # assert !@n::LoadPathCheck.current_loaded_features.include?(File.join(namespace_dir, 'blank2.rb'))
    # assert @n::LoadPathCheck.require_blank2
    # assert @n::LoadPathCheck.current_loaded_features.include?(File.join(namespace_dir, 'blank2.rb'))

    assert !$LOADED_FEATURES.include?(File.join(namespace_dir, 'blank1.rb'))
    assert !$LOADED_FEATURES.include?(File.join(namespace_dir, 'blank2.rb'))
  end
end
