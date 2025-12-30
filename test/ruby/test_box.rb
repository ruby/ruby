# frozen_string_literal: true

require 'test/unit'

class TestBox < Test::Unit::TestCase
  EXPERIMENTAL_WARNING_LINE_PATTERNS = [
    /ruby(\.exe)?: warning: Ruby::Box is experimental, and the behavior may change in the future!/,
    %r{See https://docs.ruby-lang.org/en/(master|\d\.\d)/Ruby/Box.html for known issues, etc.}
  ]
  ENV_ENABLE_BOX = {'RUBY_BOX' => '1', 'TEST_DIR' => __dir__}

  def setup
    @box = nil
    @dir = __dir__
  end

  def teardown
    @box = nil
  end

  def setup_box
    pend unless Ruby::Box.enabled?
    @box = Ruby::Box.new
  end

  def test_box_availability_in_default
    assert_separately(['RUBY_BOX'=>nil], __FILE__, __LINE__, "#{<<~"begin;"}\n#{<<~'end;'}", ignore_stderr: true)
    begin;
      assert_nil ENV['RUBY_BOX']
      assert !Ruby::Box.enabled?
    end;
  end

  def test_box_availability_when_enabled
    assert_separately([ENV_ENABLE_BOX], __FILE__, __LINE__, "#{<<~"begin;"}\n#{<<~'end;'}", ignore_stderr: true)
    begin;
      assert '1', ENV['RUBY_BOX']
      assert Ruby::Box.enabled?
    end;
  end

  def test_current_box_in_main
    assert_separately([ENV_ENABLE_BOX], __FILE__, __LINE__, "#{<<~"begin;"}\n#{<<~'end;'}", ignore_stderr: true)
    begin;
      assert_equal Ruby::Box.main, Ruby::Box.current
      assert Ruby::Box.main.main?
    end;
  end

  def test_require_rb_separately
    setup_box

    assert_raise(NameError) { BOX_A }
    assert_raise(NameError) { BOX_B }

    @box.require(File.join(__dir__, 'box', 'a.1_1_0'))

    assert_not_nil @box::BOX_A
    assert_not_nil @box::BOX_B
    assert_equal "1.1.0", @box::BOX_A::VERSION
    assert_equal "yay 1.1.0", @box::BOX_A.new.yay
    assert_equal "1.1.0", @box::BOX_B::VERSION
    assert_equal "yay_b1", @box::BOX_B.yay

    assert_raise(NameError) { BOX_A }
    assert_raise(NameError) { BOX_B }
  end

  def test_require_relative_rb_separately
    setup_box

    assert_raise(NameError) { BOX_A }
    assert_raise(NameError) { BOX_B }

    @box.require_relative('box/a.1_1_0')

    assert_not_nil @box::BOX_A
    assert_not_nil @box::BOX_B
    assert_equal "1.1.0", @box::BOX_A::VERSION
    assert_equal "yay 1.1.0", @box::BOX_A.new.yay
    assert_equal "1.1.0", @box::BOX_B::VERSION
    assert_equal "yay_b1", @box::BOX_B.yay

    assert_raise(NameError) { BOX_A }
    assert_raise(NameError) { BOX_B }
  end

  def test_load_separately
    setup_box

    assert_raise(NameError) { BOX_A }
    assert_raise(NameError) { BOX_B }

    @box.load(File.join(__dir__, 'box', 'a.1_1_0.rb'))

    assert_not_nil @box::BOX_A
    assert_not_nil @box::BOX_B
    assert_equal "1.1.0", @box::BOX_A::VERSION
    assert_equal "yay 1.1.0", @box::BOX_A.new.yay
    assert_equal "1.1.0", @box::BOX_B::VERSION
    assert_equal "yay_b1", @box::BOX_B.yay

    assert_raise(NameError) { BOX_A }
    assert_raise(NameError) { BOX_B }
  end

  def test_box_in_box
    setup_box

    assert_raise(NameError) { BOX1 }
    assert_raise(NameError) { BOX_A }
    assert_raise(NameError) { BOX_B }

    @box.require_relative('box/box')

    assert_not_nil @box::BOX1
    assert_not_nil @box::BOX1::BOX_A
    assert_not_nil @box::BOX1::BOX_B
    assert_equal "1.1.0", @box::BOX1::BOX_A::VERSION
    assert_equal "yay 1.1.0", @box::BOX1::BOX_A.new.yay
    assert_equal "1.1.0", @box::BOX1::BOX_B::VERSION
    assert_equal "yay_b1", @box::BOX1::BOX_B.yay

    assert_raise(NameError) { BOX1 }
    assert_raise(NameError) { BOX_A }
    assert_raise(NameError) { BOX_B }
  end

  def test_require_rb_2versiobox
    setup_box

    assert_raise(NameError) { BOX_A }

    @box.require(File.join(__dir__, 'box', 'a.1_2_0'))
    assert_equal "1.2.0", @box::BOX_A::VERSION
    assert_equal "yay 1.2.0", @box::BOX_A.new.yay

    n2 = Ruby::Box.new
    n2.require(File.join(__dir__, 'box', 'a.1_1_0'))
    assert_equal "1.1.0", n2::BOX_A::VERSION
    assert_equal "yay 1.1.0", n2::BOX_A.new.yay

    # recheck @box is not affected by the following require
    assert_equal "1.2.0", @box::BOX_A::VERSION
    assert_equal "yay 1.2.0", @box::BOX_A.new.yay

    assert_raise(NameError) { BOX_A }
  end

  def test_raising_errors_in_require
    setup_box

    assert_raise(RuntimeError, "Yay!") { @box.require(File.join(__dir__, 'box', 'raise')) }
    assert Ruby::Box.current.inspect.include?("main")
  end

  def test_autoload_in_box
    setup_box

    assert_raise(NameError) { BOX_A }

    @box.require_relative('box/autoloading')
    # autoloaded A is visible from global
    assert_equal '1.1.0', @box::BOX_A::VERSION

    assert_raise(NameError) { BOX_A }

    # autoload trigger BOX_B::BAR is valid even from global
    assert_equal 'bar_b1', @box::BOX_B::BAR

    assert_raise(NameError) { BOX_A }
    assert_raise(NameError) { BOX_B }
  end

  def test_continuous_top_level_method_in_a_box
    setup_box

    @box.require_relative('box/define_toplevel')
    @box.require_relative('box/call_toplevel')

    assert_raise(NameError) { foo }
  end

  def test_top_level_methods_in_box
    pend # TODO: fix loading/current box detection
    setup_box
    @box.require_relative('box/top_level')
    assert_equal "yay!", @box::Foo.foo
    assert_raise(NameError) { yaaay }
    assert_equal "foo", @box::Bar.bar
    assert_raise_with_message(RuntimeError, "boooo") { @box::Baz.baz }
  end

  def test_proc_defined_in_box_refers_module_in_box
    setup_box

    # require_relative dosn't work well in assert_separately even with __FILE__ and __LINE__
    assert_separately([ENV_ENABLE_BOX], __FILE__, __LINE__, "here = '#{__dir__}'; #{<<~"begin;"}\n#{<<~'end;'}", ignore_stderr: true)
    begin;
      box1 = Ruby::Box.new
      box1.require("#{here}/box/proc_callee")
      proc_v = box1::Foo.callee
      assert_raise(NameError) { Target }
      assert box1::Target
      assert_equal "fooooo", proc_v.call # refers Target in the box box1
      box1.require("#{here}/box/proc_caller")
      assert_equal "fooooo", box1::Bar.caller(proc_v)

      box2 = Ruby::Box.new
      box2.require("#{here}/box/proc_caller")
      assert_raise(NameError) { box2::Target }
      assert_equal "fooooo", box2::Bar.caller(proc_v) # refers Target in the box box1
    end;
  end

  def test_proc_defined_globally_refers_global_module
    setup_box

    # require_relative dosn't work well in assert_separately even with __FILE__ and __LINE__
    assert_separately([ENV_ENABLE_BOX], __FILE__, __LINE__, "here = '#{__dir__}'; #{<<~"begin;"}\n#{<<~'end;'}", ignore_stderr: true)
    begin;
      require("#{here}/box/proc_callee")
      def Target.foo
        "yay"
      end
      proc_v = Foo.callee
      assert Target
      assert_equal "yay", proc_v.call # refers global Foo
      box1 = Ruby::Box.new
      box1.require("#{here}/box/proc_caller")
      assert_equal "yay", box1::Bar.caller(proc_v)

      box2 = Ruby::Box.new
      box2.require("#{here}/box/proc_callee")
      box2.require("#{here}/box/proc_caller")
      assert_equal "fooooo", box2::Foo.callee.call
      assert_equal "yay", box2::Bar.caller(proc_v) # should refer the global Target, not Foo in box2
    end;
  end

  def test_instance_variable
    setup_box

    @box.require_relative('box/instance_variables')

    assert_equal [], String.instance_variables
    assert_equal [:@str_ivar1, :@str_ivar2], @box::StringDelegatorObj.instance_variables
    assert_equal 111, @box::StringDelegatorObj.str_ivar1
    assert_equal 222, @box::StringDelegatorObj.str_ivar2
    assert_equal 222, @box::StringDelegatorObj.instance_variable_get(:@str_ivar2)

    @box::StringDelegatorObj.instance_variable_set(:@str_ivar3, 333)
    assert_equal 333, @box::StringDelegatorObj.instance_variable_get(:@str_ivar3)
    @box::StringDelegatorObj.remove_instance_variable(:@str_ivar1)
    assert_nil @box::StringDelegatorObj.str_ivar1
    assert_equal [:@str_ivar2, :@str_ivar3], @box::StringDelegatorObj.instance_variables

    assert_equal [], String.instance_variables
  end

  def test_methods_added_in_box_are_invisible_globally
    setup_box

    @box.require_relative('box/string_ext')

    assert_equal "yay", @box::Bar.yay

    assert_raise(NoMethodError){ String.new.yay }
  end

  def test_continuous_method_definitions_in_a_box
    setup_box

    @box.require_relative('box/string_ext')
    assert_equal "yay", @box::Bar.yay

    @box.require_relative('box/string_ext_caller')
    assert_equal "yay", @box::Foo.yay

    @box.require_relative('box/string_ext_calling')
  end

  def test_methods_added_in_box_later_than_caller_code
    setup_box

    @box.require_relative('box/string_ext_caller')
    @box.require_relative('box/string_ext')

    assert_equal "yay", @box::Bar.yay
    assert_equal "yay", @box::Foo.yay
  end

  def test_method_added_in_box_are_available_on_eval
    setup_box

    @box.require_relative('box/string_ext')
    @box.require_relative('box/string_ext_eval_caller')

    assert_equal "yay", @box::Baz.yay
  end

  def test_method_added_in_box_are_available_on_eval_with_binding
    setup_box

    @box.require_relative('box/string_ext')
    @box.require_relative('box/string_ext_eval_caller')

    assert_equal "yay, yay!", @box::Baz.yay_with_binding
  end

  def test_methods_and_constants_added_by_include
    setup_box

    @box.require_relative('box/open_class_with_include')

    assert_equal "I'm saying foo 1", @box::OpenClassWithInclude.say
    assert_equal "I'm saying foo 1", @box::OpenClassWithInclude.say_foo
    assert_equal "I'm saying foo 1", @box::OpenClassWithInclude.say_with_obj("wow")

    assert_raise(NameError) { String::FOO }

    assert_equal "foo 1", @box::OpenClassWithInclude.refer_foo
  end
end

module ProcLookupTestA
  module B
    VALUE = 111
  end
end

class TestBox < Test::Unit::TestCase
  def make_proc_from_block(&b)
    b
  end

  def test_proc_from_main_works_with_global_definitions
    setup_box

    @box.require_relative('box/procs')

    proc_and_labels = [
      [Proc.new { String.new.yay }, "Proc.new"],
      [proc { String.new.yay }, "proc{}"],
      [lambda { String.new.yay }, "lambda{}"],
      [->(){ String.new.yay }, "->(){}"],
      [make_proc_from_block { String.new.yay }, "make_proc_from_block"],
      [@box::ProcInBox.make_proc_from_block { String.new.yay }, "make_proc_from_block in @box"],
    ]

    proc_and_labels.each do |str_pr|
      pr, pr_label = str_pr
      assert_raise(NoMethodError, "NoMethodError expected: #{pr_label}, called in main") { pr.call }
      assert_raise(NoMethodError, "NoMethodError expected: #{pr_label}, called in @box") { @box::ProcInBox.call_proc(pr) }
    end

    const_and_labels = [
      [Proc.new { ProcLookupTestA::B::VALUE }, "Proc.new"],
      [proc { ProcLookupTestA::B::VALUE }, "proc{}"],
      [lambda { ProcLookupTestA::B::VALUE }, "lambda{}"],
      [->(){ ProcLookupTestA::B::VALUE }, "->(){}"],
      [make_proc_from_block { ProcLookupTestA::B::VALUE }, "make_proc_from_block"],
      [@box::ProcInBox.make_proc_from_block { ProcLookupTestA::B::VALUE }, "make_proc_from_block in @box"],
    ]

    const_and_labels.each do |const_pr|
      pr, pr_label = const_pr
      assert_equal 111, pr.call, "111 expected, #{pr_label} called in main"
      assert_equal 111, @box::ProcInBox.call_proc(pr), "111 expected, #{pr_label} called in @box"
    end
  end

  def test_proc_from_box_works_with_definitions_in_box
    setup_box

    @box.require_relative('box/procs')

    proc_types = [:proc_new, :proc_f, :lambda_f, :lambda_l, :block]

    proc_types.each do |proc_type|
      assert_equal 222, @box::ProcInBox.make_const_proc(proc_type).call, "ProcLookupTestA::B::VALUE should be 222 in @box"
      assert_equal "foo", @box::ProcInBox.make_str_const_proc(proc_type).call, "String::FOO should be \"foo\" in @box"
      assert_equal "yay", @box::ProcInBox.make_str_proc(proc_type).call, "String#yay should be callable in @box"
      #
      # TODO: method calls not-in-methods nor procs can't handle the current box correctly.
      #
      # assert_equal "yay,foo,222",
      #              @box::ProcInBox.const_get(('CONST_' + proc_type.to_s.upcase).to_sym).call,
      #              "Proc assigned to constants should refer constants correctly in @box"
    end
  end

  def test_class_module_singleton_methods
    setup_box

    @box.require_relative('box/singleton_methods')

    assert_equal "Good evening!", @box::SingletonMethods.string_greeing # def self.greeting
    assert_equal 42, @box::SingletonMethods.integer_answer # class << self; def answer
    assert_equal([], @box::SingletonMethods.array_blank) # def self.blank w/ instance methods
    assert_equal({status: 200, body: 'OK'}, @box::SingletonMethods.hash_http_200) # class << self; def ... w/ instance methods

    assert_equal([4, 4], @box::SingletonMethods.array_instance_methods_return_size([1, 2, 3, 4]))
    assert_equal([3, 3], @box::SingletonMethods.hash_instance_methods_return_size({a: 2, b: 4, c: 8}))

    assert_raise(NoMethodError) { String.greeting }
    assert_raise(NoMethodError) { Integer.answer }
    assert_raise(NoMethodError) { Array.blank }
    assert_raise(NoMethodError) { Hash.http_200 }
  end

  def test_add_constants_in_box
    setup_box

    @box.require('envutil')

    String.const_set(:STR_CONST0, 999)
    assert_equal 999, String::STR_CONST0
    assert_equal 999, String.const_get(:STR_CONST0)

    assert_raise(NameError) { String.const_get(:STR_CONST1) }
    assert_raise(NameError) { String::STR_CONST2 }
    assert_raise(NameError) { String::STR_CONST3 }
    assert_raise(NameError) { Integer.const_get(:INT_CONST1) }

    EnvUtil.verbose_warning do
      @box.require_relative('box/consts')
    end

    assert_equal 999, String::STR_CONST0
    assert_raise(NameError) { String::STR_CONST1 }
    assert_raise(NameError) { String::STR_CONST2 }
    assert_raise(NameError) { Integer::INT_CONST1 }

    assert_not_nil @box::ForConsts.refer_all

    assert_equal 112, @box::ForConsts.refer1
    assert_equal 112, @box::ForConsts.get1
    assert_equal 112, @box::ForConsts::CONST1
    assert_equal 222, @box::ForConsts.refer2
    assert_equal 222, @box::ForConsts.get2
    assert_equal 222, @box::ForConsts::CONST2
    assert_equal 333, @box::ForConsts.refer3
    assert_equal 333, @box::ForConsts.get3
    assert_equal 333, @box::ForConsts::CONST3

    @box::EnvUtil.suppress_warning do
      @box::ForConsts.const_set(:CONST3, 334)
    end
    assert_equal 334, @box::ForConsts::CONST3
    assert_equal 334, @box::ForConsts.refer3
    assert_equal 334, @box::ForConsts.get3

    assert_equal 10, @box::ForConsts.refer_top_const

    # use Proxy object to use usual methods instead of singleton methods
    proxy = @box::ForConsts::Proxy.new

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

    setup_box

    assert_equal "\n", $-0 # equal to $/, line splitter
    assert_equal nil, $,   # field splitter

    @box.require_relative('box/global_vars')

    # read first
    assert_equal "\n", @box::LineSplitter.read
    @box::LineSplitter.write("\r\n")
    assert_equal "\r\n", @box::LineSplitter.read
    assert_equal "\n", $-0

    # write first
    @box::FieldSplitter.write(",")
    assert_equal ",", @box::FieldSplitter.read
    assert_equal nil, $,

    # used only in box
    assert !global_variables.include?(:$used_only_in_box)
    @box::UniqueGvar.write(123)
    assert_equal 123, @box::UniqueGvar.read
    assert_nil $used_only_in_box

    # Kernel#global_variables returns the sum of all gvars.
    global_gvars = global_variables.sort
    assert_equal global_gvars, @box::UniqueGvar.gvars_in_box.sort
    @box::UniqueGvar.write_only(456)
    assert_equal (global_gvars + [:$write_only_var_in_box]).sort, @box::UniqueGvar.gvars_in_box.sort
    assert_equal (global_gvars + [:$write_only_var_in_box]).sort, global_variables.sort
  ensure
    EnvUtil.suppress_warning do
      $-0 = default_l
      $, = default_f
    end
  end

  def test_load_path_and_loaded_features
    setup_box

    assert $LOAD_PATH.respond_to?(:resolve_feature_path)

    @box.require_relative('box/load_path')

    assert_not_equal $LOAD_PATH, @box::LoadPathCheck::FIRST_LOAD_PATH

    assert @box::LoadPathCheck::FIRST_LOAD_PATH_RESPOND_TO_RESOLVE

    box_dir = File.join(__dir__, 'box')
    # TODO: $LOADED_FEATURES in method calls should refer the current box in addition to the loading box.
    # assert @box::LoadPathCheck.current_loaded_features.include?(File.join(box_dir, 'blank1.rb'))
    # assert !@box::LoadPathCheck.current_loaded_features.include?(File.join(box_dir, 'blank2.rb'))
    # assert @box::LoadPathCheck.require_blank2
    # assert @box::LoadPathCheck.current_loaded_features.include?(File.join(box_dir, 'blank2.rb'))

    assert !$LOADED_FEATURES.include?(File.join(box_dir, 'blank1.rb'))
    assert !$LOADED_FEATURES.include?(File.join(box_dir, 'blank2.rb'))
  end

  def test_eval_basic
    setup_box

    # Test basic evaluation
    result = @box.eval("1 + 1")
    assert_equal 2, result

    # Test string evaluation
    result = @box.eval("'hello ' + 'world'")
    assert_equal "hello world", result
  end

  def test_eval_with_constants
    setup_box

    # Define a constant in the box via eval
    @box.eval("TEST_CONST = 42")
    assert_equal 42, @box::TEST_CONST

    # Constant should not be visible in main box
    assert_raise(NameError) { TEST_CONST }
  end

  def test_eval_with_classes
    setup_box

    # Define a class in the box via eval
    @box.eval("class TestClass; def hello; 'from box'; end; end")

    # Class should be accessible in the box
    instance = @box::TestClass.new
    assert_equal "from box", instance.hello

    # Class should not be visible in main box
    assert_raise(NameError) { TestClass }
  end

  def test_eval_isolation
    setup_box

    # Create another box
    n2 = Ruby::Box.new

    # Define different constants in each box
    @box.eval("ISOLATION_TEST = 'first'")
    n2.eval("ISOLATION_TEST = 'second'")

    # Each box should have its own constant
    assert_equal "first", @box::ISOLATION_TEST
    assert_equal "second", n2::ISOLATION_TEST

    # Constants should not interfere with each other
    assert_not_equal @box::ISOLATION_TEST, n2::ISOLATION_TEST
  end

  def test_eval_with_variables
    setup_box

    # Test local variable access (should work within the eval context)
    result = @box.eval("x = 10; y = 20; x + y")
    assert_equal 30, result
  end

  def test_eval_error_handling
    setup_box

    # Test syntax error
    assert_raise(SyntaxError) { @box.eval("1 +") }

    # Test name error
    assert_raise(NameError) { @box.eval("undefined_variable") }

    # Test that box is properly restored after error
    begin
      @box.eval("raise RuntimeError, 'test error'")
    rescue RuntimeError
      # Should be able to continue using the box
      result = @box.eval("2 + 2")
      assert_equal 4, result
    end
  end

  # Tests which run always (w/o RUBY_BOX=1 globally)

  def test_prelude_gems_and_loaded_features
    assert_in_out_err([ENV_ENABLE_BOX, "--enable=gems"], "#{<<-"begin;"}\n#{<<-'end;'}") do |output, error|
      begin;
        puts ["before:", $LOADED_FEATURES.select{ it.end_with?("/bundled_gems.rb") }&.first].join
        puts ["before:", $LOADED_FEATURES.select{ it.end_with?("/error_highlight.rb") }&.first].join

        require "error_highlight"

        puts ["after:", $LOADED_FEATURES.select{ it.end_with?("/bundled_gems.rb") }&.first].join
        puts ["after:", $LOADED_FEATURES.select{ it.end_with?("/error_highlight.rb") }&.first].join
      end;

      # No additional warnings except for experimental warnings
      assert_equal 2, error.size
      assert_match EXPERIMENTAL_WARNING_LINE_PATTERNS[0], error[0]
      assert_match EXPERIMENTAL_WARNING_LINE_PATTERNS[1], error[1]

      assert_includes output.grep(/^before:/).join("\n"), '/bundled_gems.rb'
      assert_includes output.grep(/^before:/).join("\n"), '/error_highlight.rb'
      assert_includes output.grep(/^after:/).join("\n"), '/bundled_gems.rb'
      assert_includes output.grep(/^after:/).join("\n"), '/error_highlight.rb'
    end
  end

  def test_prelude_gems_and_loaded_features_with_disable_gems
    assert_in_out_err([ENV_ENABLE_BOX, "--disable=gems"], "#{<<-"begin;"}\n#{<<-'end;'}") do |output, error|
      begin;
        puts ["before:", $LOADED_FEATURES.select{ it.end_with?("/bundled_gems.rb") }&.first].join
        puts ["before:", $LOADED_FEATURES.select{ it.end_with?("/error_highlight.rb") }&.first].join

        require "error_highlight"

        puts ["after:", $LOADED_FEATURES.select{ it.end_with?("/bundled_gems.rb") }&.first].join
        puts ["after:", $LOADED_FEATURES.select{ it.end_with?("/error_highlight.rb") }&.first].join
      end;

      assert_equal 2, error.size
      assert_match EXPERIMENTAL_WARNING_LINE_PATTERNS[0], error[0]
      assert_match EXPERIMENTAL_WARNING_LINE_PATTERNS[1], error[1]

      refute_includes output.grep(/^before:/).join("\n"), '/bundled_gems.rb'
      refute_includes output.grep(/^before:/).join("\n"), '/error_highlight.rb'
      refute_includes output.grep(/^after:/).join("\n"), '/bundled_gems.rb'
      assert_includes output.grep(/^after:/).join("\n"), '/error_highlight.rb'
    end
  end

  def test_root_and_main_methods
    assert_separately([ENV_ENABLE_BOX], __FILE__, __LINE__, "#{<<~"begin;"}\n#{<<~'end;'}", ignore_stderr: true)
    begin;
      pend unless Ruby::Box.respond_to?(:root) and Ruby::Box.respond_to?(:main) # for RUBY_DEBUG > 0

      assert Ruby::Box.root.respond_to?(:root?)
      assert Ruby::Box.main.respond_to?(:main?)

      assert Ruby::Box.root.root?
      assert Ruby::Box.main.main?
      assert_equal Ruby::Box.main, Ruby::Box.current

      $a = 1
      $LOADED_FEATURES.push("/tmp/foobar")

      assert_equal 2, Ruby::Box.root.eval('$a = 2; $a')
      assert !Ruby::Box.root.eval('$LOADED_FEATURES.push("/tmp/barbaz"); $LOADED_FEATURES.include?("/tmp/foobar")')
      assert "FooClass", Ruby::Box.root.eval('class FooClass; end; Object.const_get(:FooClass).to_s')

      assert_equal 1, $a
      assert !$LOADED_FEATURES.include?("/tmp/barbaz")
      assert !Object.const_defined?(:FooClass)
    end;
  end

  def test_basic_box_detections
    assert_separately([ENV_ENABLE_BOX], __FILE__, __LINE__, "#{<<~"begin;"}\n#{<<~'end;'}", ignore_stderr: true)
    begin;
      box = Ruby::Box.new
      $gvar1 = 'bar'
      code = <<~EOC
      BOX1 = Ruby::Box.current
      $gvar1 = 'foo'

      def toplevel = $gvar1

      class Foo
        BOX2 = Ruby::Box.current
        BOX2_proc = ->(){ BOX2 }
        BOX3_proc = ->(){ Ruby::Box.current }

        def box4 = Ruby::Box.current
        def self.box5 = BOX2
        def self.box6 = Ruby::Box.current
        def self.box6_proc = ->(){ Ruby::Box.current }
        def self.box7
          res = []
          [1,2].chunk{ it.even? }.each do |bool, members|
            res << Ruby::Box.current.object_id.to_s + ":" + bool.to_s + ":" + members.map(&:to_s).join(",")
          end
          res
        end

        def self.yield_block = yield
        def self.call_block(&b) = b.call

        def self.gvar1 = $gvar1
        def self.call_toplevel = toplevel
      end
      FOO_NAME = Foo.name

      module Kernel
        def foo_box = Ruby::Box.current
        module_function :foo_box
      end

      BOX_X = Foo.new.box4
      BOX_Y = foo_box
      EOC
      box.eval(code)
      outer = Ruby::Box.current
      assert_equal box, box::BOX1 # on TOP frame
      assert_equal box, box::Foo::BOX2 # on CLASS frame
      assert_equal box, box::Foo::BOX2_proc.call # proc -> a const on CLASS
      assert_equal box, box::Foo::BOX3_proc.call # proc -> the current
      assert_equal box, box::Foo.new.box4 # instance method  -> the current
      assert_equal box, box::Foo.box5     # singleton method -> a const on CLASS
      assert_equal box, box::Foo.box6     # singleton method -> the current
      assert_equal box, box::Foo.box6_proc.call # method returns a proc -> the current

      # a block after CFUNC/IFUNC in a method -> the current
      assert_equal ["#{box.object_id}:false:1", "#{box.object_id}:true:2"], box::Foo.box7

      assert_equal outer, box::Foo.yield_block{ Ruby::Box.current } # method yields
      assert_equal outer, box::Foo.call_block{ Ruby::Box.current }  # method calls a block

      assert_equal 'foo', box::Foo.gvar1 # method refers gvar
      assert_equal 'bar', $gvar1        # gvar value out of the box
      assert_equal 'foo', box::Foo.call_toplevel # toplevel method referring gvar

      assert_equal box, box::BOX_X # on TOP frame, referring a class in the current
      assert_equal box, box::BOX_Y # on TOP frame, referring Kernel method defined by a CFUNC method

      assert_equal "Foo", box::FOO_NAME
      assert_equal "Foo", box::Foo.name
    end;
  end

  def test_loading_extension_libs_in_main_box_1
    pend if /mswin|mingw/ =~ RUBY_PLATFORM # timeout on windows environments
    assert_separately([ENV_ENABLE_BOX], __FILE__, __LINE__, "#{<<~"begin;"}\n#{<<~'end;'}", ignore_stderr: true)
    begin;
      require "prism"
      require "optparse"
      require "date"
      require "time"
      require "delegate"
      require "singleton"
      require "pp"
      require "fileutils"
      require "tempfile"
      require "tmpdir"
      require "json"
      require "psych"
      require "yaml"
      expected = 1
      assert_equal expected, 1
    end;
  end

  def test_loading_extension_libs_in_main_box_2
    pend if /mswin|mingw/ =~ RUBY_PLATFORM # timeout on windows environments
    assert_separately([ENV_ENABLE_BOX], __FILE__, __LINE__, "#{<<~"begin;"}\n#{<<~'end;'}", ignore_stderr: true)
    begin;
      require "zlib"
      require "open3"
      require "ipaddr"
      require "net/http"
      require "openssl"
      require "socket"
      require "uri"
      require "digest"
      require "erb"
      require "stringio"
      require "monitor"
      require "timeout"
      require "securerandom"
      expected = 1
      assert_equal expected, 1
    end;
  end

  def test_mark_box_object_referred_only_from_binding
    assert_separately([ENV_ENABLE_BOX], __FILE__, __LINE__, "#{<<~"begin;"}\n#{<<~'end;'}", ignore_stderr: true)
    begin;
      box = Ruby::Box.new
      box.eval('class Integer; def +(*)=42; end')
      b = box.eval('binding')
      box = nil # remove direct reference to the box

      assert_equal 42, b.eval('1+2')

      GC.stress = true
      GC.start

      assert_equal 42, b.eval('1+2')
    end;
  end

  def test_loaded_extension_deleted_in_user_box
    require 'tmpdir'
    Dir.mktmpdir do |tmpdir|
      env = ENV_ENABLE_BOX.merge({'TMPDIR'=>tmpdir})
      assert_ruby_status([env], "#{<<~"begin;"}\n#{<<~'end;'}")
      begin;
        require "json"
      end;
      assert_empty(Dir.children(tmpdir))
    end
  end

  def test_root_box_iclasses_should_be_boxable
    assert_separately([ENV_ENABLE_BOX], __FILE__, __LINE__, "#{<<~"begin;"}\n#{<<~'end;'}", ignore_stderr: true)
    begin;
      Ruby::Box.root.eval("class IMath; include Math; end") # (*)
      module Math
        def foo = :foo
      end
      # This test crashes here if iclasses (created at the line (*) is not boxable)
      class IMath2; include Math; end
      assert_equal :foo, IMath2.new.foo
      assert_raise NoMethodError do
        Ruby::Box.root.eval("IMath.new.foo")
      end
    end;
  end
end
