# frozen_string_literal: false
require 'test/unit'

class TestEval < Test::Unit::TestCase

  @ivar = 12
  @@cvar = 13
  $gvar__eval = 14
  Const = 15

  def ruby(*args)
    args = ['-e', '$>.write($<.read)'] if args.empty?
    ruby = EnvUtil.rubybin
    f = IO.popen([ruby] + args, 'r+')
    yield(f)
  ensure
    f.close unless !f || f.closed?
  end

  def test_eval_basic
    assert_equal nil,   eval("nil")
    assert_equal true,  eval("true")
    assert_equal false, eval("false")
    assert_equal self,  eval("self")
    assert_equal 1,     eval("1")
    assert_equal :sym,  eval(":sym")

    assert_equal 11,    eval("11")
    @ivar = 12
    assert_equal 12,    eval("@ivar")
    assert_equal 13,    eval("@@cvar")
    assert_equal 14,    eval("$gvar__eval")
    assert_equal 15,    eval("Const")

    assert_equal 16,    eval("7 + 9")
    assert_equal 17,    eval("17.to_i")
    assert_equal "18",  eval(%q("18"))
    assert_equal "19",  eval(%q("1#{9}"))

    1.times {
      assert_equal 12,  eval("@ivar")
      assert_equal 13,  eval("@@cvar")
      assert_equal 14,  eval("$gvar__eval")
      assert_equal 15,  eval("Const")
    }
  end

  def test_eval_binding_basic
    assert_equal nil,   eval("nil", binding())
    assert_equal true,  eval("true", binding())
    assert_equal false, eval("false", binding())
    assert_equal self,  eval("self", binding())
    assert_equal 1,     eval("1", binding())
    assert_equal :sym,  eval(":sym", binding())

    assert_equal 11,    eval("11", binding())
    @ivar = 12
    assert_equal 12,    eval("@ivar", binding())
    assert_equal 13,    eval("@@cvar", binding())
    assert_equal 14,    eval("$gvar__eval", binding())
    assert_equal 15,    eval("Const", binding())

    assert_equal 16,    eval("7 + 9", binding())
    assert_equal 17,    eval("17.to_i", binding())
    assert_equal "18",  eval(%q("18"), binding())
    assert_equal "19",  eval(%q("1#{9}"), binding())

    1.times {
      assert_equal 12,  eval("@ivar")
      assert_equal 13,  eval("@@cvar")
      assert_equal 14,  eval("$gvar__eval")
      assert_equal 15,  eval("Const")
    }
  end

  def test_module_eval_string_basic
    c = self.class
    assert_equal nil,   c.module_eval("nil")
    assert_equal true,  c.module_eval("true")
    assert_equal false, c.module_eval("false")
    assert_equal c,     c.module_eval("self")
    assert_equal :sym,  c.module_eval(":sym")
    assert_equal 11,    c.module_eval("11")
    @ivar = 12
    assert_equal 12,    c.module_eval("@ivar")
    assert_equal 13,    c.module_eval("@@cvar")
    assert_equal 14,    c.module_eval("$gvar__eval")
    assert_equal 15,    c.module_eval("Const")
    assert_equal 16,    c.module_eval("7 + 9")
    assert_equal 17,    c.module_eval("17.to_i")
    assert_equal "18",  c.module_eval(%q("18"))
    assert_equal "19",  c.module_eval(%q("1#{9}"))

    @ivar = 12
    1.times {
      assert_equal 12,  c.module_eval("@ivar")
      assert_equal 13,  c.module_eval("@@cvar")
      assert_equal 14,  c.module_eval("$gvar__eval")
      assert_equal 15,  c.module_eval("Const")
    }
  end

  def test_module_eval_block_basic
    c = self.class
    assert_equal nil,   c.module_eval { nil }
    assert_equal true,  c.module_eval { true }
    assert_equal false, c.module_eval { false }
    assert_equal c,     c.module_eval { self }
    assert_equal :sym,  c.module_eval { :sym }
    assert_equal 11,    c.module_eval { 11 }
    @ivar = 12
    assert_equal 12,    c.module_eval { @ivar }
    assert_equal 13,    c.module_eval { @@cvar }
    assert_equal 14,    c.module_eval { $gvar__eval }
    assert_equal 15,    c.module_eval { Const }
    assert_equal 16,    c.module_eval { 7 + 9 }
    assert_equal 17,    c.module_eval { "17".to_i }
    assert_equal "18",  c.module_eval { "18" }
    assert_equal "19",  c.module_eval { "1#{9}" }

    @ivar = 12
    1.times {
      assert_equal 12,  c.module_eval { @ivar }
      assert_equal 13,  c.module_eval { @@cvar }
      assert_equal 14,  c.module_eval { $gvar__eval }
      assert_equal 15,  c.module_eval { Const }
    }
  end

  def test_module_eval_block_symbol
    assert_equal "Math", Math.module_eval(&:to_s)
  end

  def forall_TYPE
    objects = [Object.new, [], nil, true, false] # TODO: check
    objects.each do |obj|
      obj.instance_variable_set :@ivar, 12 unless obj.frozen?
      yield obj
    end
  end

  def test_instance_eval_string_basic
    forall_TYPE do |o|
      assert_equal nil,   o.instance_eval("nil")
      assert_equal true,  o.instance_eval("true")
      assert_equal false, o.instance_eval("false")
      assert_equal o,     o.instance_eval("self")
      assert_equal 1,     o.instance_eval("1")
      assert_equal :sym,  o.instance_eval(":sym")

      assert_equal 11,    o.instance_eval("11")
      assert_equal 12,    o.instance_eval("@ivar") unless o.frozen?
      assert_equal 13,    o.instance_eval("@@cvar")
      assert_equal 14,    o.instance_eval("$gvar__eval")
      assert_equal 15,    o.instance_eval("Const")
      assert_equal 16,    o.instance_eval("7 + 9")
      assert_equal 17,    o.instance_eval("17.to_i")
      assert_equal "18",  o.instance_eval(%q("18"))
      assert_equal "19",  o.instance_eval(%q("1#{9}"))

      1.times {
        assert_equal 12,  o.instance_eval("@ivar") unless o.frozen?
        assert_equal 13,  o.instance_eval("@@cvar")
        assert_equal 14,  o.instance_eval("$gvar__eval")
        assert_equal 15,  o.instance_eval("Const")
      }
    end
  end

  def test_instance_eval_block_basic
    forall_TYPE do |o|
      assert_equal nil,   o.instance_eval { nil }
      assert_equal true,  o.instance_eval { true }
      assert_equal false, o.instance_eval { false }
      assert_equal o,     o.instance_eval { self }
      assert_equal 1,     o.instance_eval { 1 }
      assert_equal :sym,  o.instance_eval { :sym }

      assert_equal 11,    o.instance_eval { 11 }
      assert_equal 12,    o.instance_eval { @ivar } unless o.frozen?
      assert_equal 13,    o.instance_eval { @@cvar }
      assert_equal 14,    o.instance_eval { $gvar__eval }
      assert_equal 15,    o.instance_eval { Const }
      assert_equal 16,    o.instance_eval { 7 + 9 }
      assert_equal 17,    o.instance_eval { 17.to_i }
      assert_equal "18",  o.instance_eval { "18" }
      assert_equal "19",  o.instance_eval { "1#{9}" }

      1.times {
        assert_equal 12,  o.instance_eval { @ivar } unless o.frozen?
        assert_equal 13,  o.instance_eval { @@cvar }
        assert_equal 14,  o.instance_eval { $gvar__eval }
        assert_equal 15,  o.instance_eval { Const }
      }
    end
  end

  def test_instance_eval_block_self
    # instance_eval(&block)'s self must not be sticky (jruby/jruby#2060)
    pr = proc { self }
    assert_equal self, pr.call
    o = Object.new
    assert_equal o, o.instance_eval(&pr)
    assert_equal self, pr.call
  end

  def test_instance_eval_block_symbol
    forall_TYPE do |o|
      assert_equal o.to_s, o.instance_eval(&:to_s)
    end
  end

  def test_instance_eval_cvar
    [Object.new, [], 7, :sym, true, false, nil].each do |obj|
      assert_equal(13, obj.instance_eval("@@cvar"))
      assert_equal(13, obj.instance_eval{@@cvar})
      # assert_raise(NameError){obj.instance_eval("@@cvar")}
      # assert_raise(NameError){obj.instance_eval{@@cvar}}
    end
  end

  def test_instance_eval_method
    bug2788 = '[ruby-core:28324]'
    [Object.new, [], nil, true, false].each do |o|
      assert_nothing_raised(TypeError, "#{bug2788} (#{o.inspect})") do
        o.instance_eval {
          def defd_using_instance_eval() :ok end
        }
      end
      assert_equal(:ok, o.defd_using_instance_eval)
      class << o
        remove_method :defd_using_instance_eval
      end
    end
  end

  def test_instance_eval_on_argf_singleton_class
    bug8188 = '[ruby-core:53839] [Bug #8188]'
    assert_warning('', bug8188) do
      ARGF.singleton_class.instance_eval{}
    end
  end

  class Foo
    Bar = 2
  end

  def test_instance_eval_const
    bar = nil
    assert_nothing_raised(NameError) do
      bar = Foo.new.instance_eval("Bar")
    end
    assert_equal(2, bar)
  end

  #
  # From ruby/test/ruby/test_eval.rb
  #

  def make_test_binding
    local1 = local1 = "local1"
    lambda {
      local2 = local2 = "local2"
      return binding
    }.call
  end

  def test_eval_orig
    assert_nil(eval(""))
    bad=false
    eval 'while false; bad = true; print "foo\n" end'
    assert(!bad)

    assert(eval('Object'))
    assert(eval('true'))
    assert(!eval('nil'))
    assert(!eval('false'))

    $foo = 'assert(true)'
    begin
      eval $foo
    rescue
      assert(false)
    end

    assert_equal('assert(true)', eval("$foo"))
    assert_equal(true, eval("true"))
    i = i = 5
    assert(eval("i == 5"))
    assert_equal(5, eval("i"))
    assert(eval("defined? i"))

    x = make_test_binding
    assert_equal("local1", eval("local1", x)) # normal local var
    assert_equal("local2", eval("local2", x)) # nested local var
    bad = true
    begin
      p eval("local1")
    rescue NameError		# must raise error
      bad = false
    end
    assert(!bad)

    # !! use class_eval to avoid nested definition
    x = self.class.class_eval %q(
      module EvTest
	EVTEST1 = 25
	evtest2 = 125
	evtest2 = evtest2
	binding
      end
    )
    assert_equal(25, eval("EVTEST1", x))	# constant in module
    assert_equal(125, eval("evtest2", x))	# local var in module
    bad = true
    begin
      eval("EVTEST1")
    rescue NameError		# must raise error
      bad = false
    end
    assert(!bad)

    if false
      # Ruby 2.0 doesn't see Proc as Binding
      x = proc{}
      eval "i4 = 1", x
      assert_equal(1, eval("i4", x))
      x = proc{proc{}}.call
      eval "i4 = 22", x
      assert_equal(22, eval("i4", x))
      t = []
      x = proc{proc{}}.call
      eval "(0..9).each{|i5| t[i5] = proc{i5*2}}", x
      assert_equal(8, t[4].call)
    end

    x = binding
    eval "i = 1", x
    assert_equal(1, eval("i", x))
    x = proc{binding}.call
    eval "i = 22", x
    assert_equal(22, eval("i", x))
    t = []
    x = proc{binding}.call
    eval "(0..9).each{|i5| t[i5] = proc{i5*2}}", x
    assert_equal(8, t[4].call)
    x = proc{binding}.call
    eval "for i6 in 1..1; j6=i6; end", x
    assert(eval("defined? i6", x))
    assert(eval("defined? j6", x))

    proc {
      p = binding
      eval "foo11 = 1", p
      foo22 = 5
      proc{foo11=22;foo11}.call
      proc{foo22=55}.call
      # assert_equal(eval("foo11"), eval("foo11", p))
      # assert_equal(1, eval("foo11"))
      assert_equal(eval("foo22"), eval("foo22", p))
      assert_equal(55, eval("foo22"))
    }.call

    if false
      # Ruby 2.0 doesn't see Proc as Binding
      p1 = proc{i7 = 0; proc{i7}}.call
      assert_equal(0, p1.call)
      eval "i7=5", p1
      assert_equal(5, p1.call)
      assert(!defined?(i7))
    end

    if false
      # Ruby 2.0 doesn't see Proc as Binding
      p1 = proc{i7 = 0; proc{i7}}.call
      i7 = nil
      assert_equal(0, p1.call)
      eval "i7=1", p1
      assert_equal(1, p1.call)
      eval "i7=5", p1
      assert_equal(5, p1.call)
      assert_nil(i7)
    end
  end

  def test_nil_instance_eval_cvar
    def nil.test_binding
      binding
    end
    bb = eval("nil.instance_eval \"binding\"", nil.test_binding)
    assert_raise(NameError, "[ruby-dev:24103]") { eval("@@a", bb) }
    class << nil
      remove_method :test_binding
    end
  end

  def test_fixnum_instance_eval_cvar
    assert_raise(NameError, "[ruby-dev:24213]") { 1.instance_eval "@@a" }
  end

  def test_cvar_scope_with_instance_eval
    # TODO: check
    Integer.class_eval "@@test_cvar_scope_with_instance_eval = 1" # depends on [ruby-dev:24229]
    @@test_cvar_scope_with_instance_eval = 4
    assert_equal(4, 1.instance_eval("@@test_cvar_scope_with_instance_eval"), "[ruby-dev:24223]")
    Integer.__send__(:remove_class_variable, :@@test_cvar_scope_with_instance_eval)
  end

  def test_eval_and_define_method
    assert_nothing_raised("[ruby-dev:24228]") {
      def temporally_method_for_test_eval_and_define_method(&block)
        lambda {
          class << Object.new; self end.send(:define_method, :zzz, &block)
        }
      end
      v = eval("temporally_method_for_test_eval_and_define_method {}")
      {}[0] = {}
      v.call
    }
  end

  def test_define_method_block
    cc = Class.new do
      define_method(:foo) {|&block|
        block.call if block
      }
    end

    c = cc.new
    x = "ng"
    c.foo() {x = "ok"}
    assert_equal("ok", x)
  end

  def test_define_method_toplevel
    feature6609 = '[ruby-core:45715]'
    main = eval("self", TOPLEVEL_BINDING)
    assert_nothing_raised(NoMethodError, feature6609) do
      main.instance_eval do
        define_method("feature6609_block") {feature6609}
      end
    end
    assert_equal(feature6609, feature6609_block)

    assert_nothing_raised(NoMethodError, feature6609) do
      main.instance_eval do
        define_method("feature6609_method", Object.instance_method(:feature6609_block))
      end
    end
    assert_equal(feature6609, feature6609_method)
  end

  def test_eval_using_integer_as_binding
    assert_raise(TypeError) { eval("", 1) }
  end

  def test_eval_raise
    assert_raise(RuntimeError) { eval("raise ''") }
  end

  def test_eval_with_toplevel_binding # [ruby-dev:37142]
    ruby("-e", "x = 0; eval('p x', TOPLEVEL_BINDING)") do |f|
      f.close_write
      assert_equal("0", f.read.chomp)
    end
  end

  def test_eval_ascii_incompatible
    assert_raise(ArgumentError) {eval("__ENCODING__".encode("utf-16be"))}
    assert_raise(ArgumentError) {eval("__ENCODING__".encode("utf-16le"))}
    assert_raise(ArgumentError) {eval("__ENCODING__".encode("utf-32be"))}
    assert_raise(ArgumentError) {eval("__ENCODING__".encode("utf-32le"))}
  end

  def test_instance_eval_method_proc
    bug3860 = Class.new do
      def initialize(a);
        @a=a
      end
      def get(*args)
        @a
      end
    end
    foo = bug3860.new 1
    foo_pr = foo.method(:get).to_proc
    result = foo.instance_eval(&foo_pr)
    assert_equal(1, result, 'Bug #3786, Bug #3860, [ruby-core:32501]')
  end

  def test_file_encoding
    fname = "\u{3042}".encode("euc-jp")
    assert_equal(fname, eval("__FILE__", nil, fname, 1))
  end

  def test_eval_location_fstring
    o = Object.new
    o.instance_eval "def foo() end", "generated code"
    o.instance_eval "def bar() end", "generated code"

    a, b = o.method(:foo).source_location[0],
           o.method(:bar).source_location[0]

    assert_same a, b
  end

  def test_fstring_instance_eval
    bug = "[ruby-core:78116] [Bug #12930]".freeze
    assert_same bug, (bug.instance_eval {self})
    assert_raise(FrozenError) {
      bug.instance_eval {@ivar = true}
    }
  end

  def test_gced_binding_block
    assert_normal_exit %q{
      def m
        binding
      end
      GC.stress = true
      b = nil
      tap do
        b = m {}
      end
      0.times.to_a
      b.eval('yield')
    }, '[Bug #10368]'
  end

  def orphan_proc
    proc {eval("return :ng")}
  end

  def orphan_lambda
    lambda {eval("return :ok")}
  end

  def test_return_in_eval_proc
    x = orphan_proc
    assert_raise(LocalJumpError) {x.call}
  end

  def test_return_in_eval_lambda
    x = orphan_lambda
    assert_equal(:ok, x.call)
  end
end
