# frozen_string_literal: false
require 'test/unit'

class TestProc < Test::Unit::TestCase
  def setup
    @verbose = $VERBOSE
  end

  def teardown
    $VERBOSE = @verbose
  end

  def test_proc
    p1 = proc{|i| i}
    assert_equal(2, p1.call(2))
    assert_equal(3, p1.call(3))

    p1 = proc{|i| i*2}
    assert_equal(4, p1.call(2))
    assert_equal(6, p1.call(3))

    p2 = nil
    x=0

    proc{
      iii=5				# nested local variable
      p1 = proc{|i|
        iii = i
      }
      p2 = proc {
        x = iii                 	# nested variables shared by procs
      }
      # scope of nested variables
      assert(defined?(iii))
    }.call
    assert(!defined?(iii))		# out of scope

    loop{iii=iii=5; assert(eval("defined? iii")); break}
    loop {
      iii=iii = 10
      def self.dyna_var_check
        loop {
          assert(!defined?(iii))
          break
        }
      end
      dyna_var_check
      break
    }
    p1.call(5)
    p2.call
    assert_equal(5, x)
  end

  def assert_arity(n, &block)
    meta = class << self; self; end
    b = Proc.new(&block)
    meta.class_eval {
      remove_method(:foo_arity) if method_defined?(:foo_arity)
      define_method(:foo_arity, b)
    }
    assert_equal(n, method(:foo_arity).arity)
  end

  def test_arity
    assert_equal(0, proc{}.arity)
    assert_equal(0, proc{||}.arity)
    assert_equal(1, proc{|x|}.arity)
    assert_equal(0, proc{|x=1|}.arity)
    assert_equal(2, proc{|x, y|}.arity)
    assert_equal(1, proc{|x=0, y|}.arity)
    assert_equal(0, proc{|x=0, y=0|}.arity)
    assert_equal(1, proc{|x, y=0|}.arity)
    assert_equal(-2, proc{|x, *y|}.arity)
    assert_equal(-1, proc{|x=0, *y|}.arity)
    assert_equal(-1, proc{|*x|}.arity)
    assert_equal(-1, proc{|*|}.arity)
    assert_equal(-3, proc{|x, *y, z|}.arity)
    assert_equal(-2, proc{|x=0, *y, z|}.arity)
    assert_equal(2, proc{|(x, y), z|[x,y]}.arity)
    assert_equal(1, proc{|(x, y), z=0|[x,y]}.arity)
    assert_equal(-4, proc{|x, *y, z, a|}.arity)
    assert_equal(0, proc{|**|}.arity)
    assert_equal(0, proc{|**o|}.arity)
    assert_equal(1, proc{|x, **o|}.arity)
    assert_equal(0, proc{|x=0, **o|}.arity)
    assert_equal(1, proc{|x, y=0, **o|}.arity)
    assert_equal(2, proc{|x, y=0, z, **o|}.arity)
    assert_equal(-3, proc{|x, y=0, *z, w, **o|}.arity)

    assert_equal(2, proc{|x, y=0, z, a:1|}.arity)
    assert_equal(3, proc{|x, y=0, z, a:|}.arity)
    assert_equal(-4, proc{|x, y, *rest, a:, b:, c:|}.arity)
    assert_equal(3, proc{|x, y=0, z, a:, **o|}.arity)

    assert_equal(0, lambda{}.arity)
    assert_equal(0, lambda{||}.arity)
    assert_equal(1, lambda{|x|}.arity)
    assert_equal(-1, lambda{|x=1|}.arity) # different from proc
    assert_equal(2, lambda{|x, y|}.arity)
    assert_equal(-2, lambda{|x=0, y|}.arity) # different from proc
    assert_equal(-1, lambda{|x=0, y=0|}.arity) # different from proc
    assert_equal(-2, lambda{|x, y=0|}.arity) # different from proc
    assert_equal(-2, lambda{|x, *y|}.arity)
    assert_equal(-1, lambda{|x=0, *y|}.arity)
    assert_equal(-1, lambda{|*x|}.arity)
    assert_equal(-1, lambda{|*|}.arity)
    assert_equal(-3, lambda{|x, *y, z|}.arity)
    assert_equal(-2, lambda{|x=0, *y, z|}.arity)
    assert_equal(2, lambda{|(x, y), z|[x,y]}.arity)
    assert_equal(-2, lambda{|(x, y), z=0|[x,y]}.arity)
    assert_equal(-4, lambda{|x, *y, z, a|}.arity)
    assert_equal(-1, lambda{|**|}.arity)
    assert_equal(-1, lambda{|**o|}.arity)
    assert_equal(-2, lambda{|x, **o|}.arity)
    assert_equal(-1, lambda{|x=0, **o|}.arity)
    assert_equal(-2, lambda{|x, y=0, **o|}.arity)
    assert_equal(-3, lambda{|x, y=0, z, **o|}.arity)
    assert_equal(-3, lambda{|x, y=0, *z, w, **o|}.arity)

    assert_arity(0) {}
    assert_arity(0) {||}
    assert_arity(1) {|x|}
    assert_arity(2) {|x, y|}
    assert_arity(-2) {|x, *y|}
    assert_arity(-3) {|x, *y, z|}
    assert_arity(-1) {|*x|}
    assert_arity(-1) {|*|}
    assert_arity(-1) {|**o|}
    assert_arity(-1) {|**|}
    assert_arity(-2) {|x, *y, **|}
    assert_arity(-3) {|x, *y, z, **|}
  end

  def m(x)
    lambda { x }
  end

  def m_nest0(&block)
    block
  end

  def m_nest(&block)
    [m_nest0(&block), m_nest0(&block)]
  end

  def test_eq
    a = m(1)
    b = m(2)
    assert_not_equal(a, b, "[ruby-dev:22592]")
    assert_not_equal(a.call, b.call, "[ruby-dev:22592]")

    assert_not_equal(proc {||}, proc {|x,y|}, "[ruby-dev:22599]")

    a = lambda {|x| lambda {} }.call(1)
    b = lambda {}
    assert_not_equal(a, b, "[ruby-dev:22601]")

    assert_equal(*m_nest{}, "[ruby-core:84583] Feature #14627")
  end

  def test_hash_equal
    # iseq backed proc
    p1 = proc {}
    p2 = p1.dup

    assert_equal p1.hash, p2.hash

    # ifunc backed proc
    p1 = {}.to_proc
    p2 = p1.dup

    assert_equal p1.hash, p2.hash

    # symbol backed proc
    p1 = :hello.to_proc
    p2 = :hello.to_proc

    assert_equal p1.hash, p2.hash
  end

  def test_hash_uniqueness
    def self.capture(&block)
      block
    end

    procs = Array.new(1000){capture{:foo }}
    assert_operator(procs.map(&:hash).uniq.size, :>=, 500)

    # iseq backed proc
    unique_hashes = 1000.times.map { proc {}.hash }.uniq
    assert_operator(unique_hashes.size, :>=, 500)

    # ifunc backed proc
    unique_hashes = 1000.times.map { {}.to_proc.hash }.uniq
    assert_operator(unique_hashes.size, :>=, 500)

    # symbol backed proc
    unique_hashes = 1000.times.map { |i| :"test#{i}".to_proc.hash }.uniq
    assert_operator(unique_hashes.size, :>=, 500)
  end

  def test_hash_does_not_change_after_compaction
    omit "compaction is not supported on this platform" unless GC.respond_to?(:compact)

    # [Bug #20853]
    [
      "proc {}", # iseq backed proc
      "{}.to_proc", # ifunc backed proc
      ":hello.to_proc", # symbol backed proc
    ].each do |proc|
      assert_separately([], <<~RUBY)
        p1 = #{proc}
        hash = p1.hash

        GC.verify_compaction_references(expand_heap: true, toward: :empty)

        assert_equal(hash, p1.hash, "proc is `#{proc}`")
      RUBY
    end
  end

  def test_block_par
    assert_equal(10, Proc.new{|&b| b.call(10)}.call {|x| x})
    assert_equal(12, Proc.new{|a,&b| b.call(a)}.call(12) {|x| x})
  end

  def m2
    "OK"
  end

  def block
    method(:m2).to_proc
  end

  def m1(var)
    var
  end

  def m_block_given?
    m1(block_given?)
  end

  # [yarv-dev:777] block made by Method#to_proc
  def test_method_to_proc
    b = block()
    assert_equal "OK", b.call
    b = b.binding
    assert_instance_of(Binding, b, '[ruby-core:25589]')
    bug10432 = '[ruby-core:65919] [Bug #10432]'
    assert_same(self, b.receiver, bug10432)
    assert_not_send [b, :local_variable_defined?, :value]
    assert_raise(NameError) {
      b.local_variable_get(:value)
    }
    assert_equal 42, b.local_variable_set(:value, 42)
    assert_send [b, :local_variable_defined?, :value]
    assert_equal 42, b.local_variable_get(:value)
  end

  def test_block_given_method
    verbose_bak, $VERBOSE = $VERBOSE, nil
    m = method(:m_block_given?)
    assert(!m.call, "without block")
    assert(m.call {}, "with block")
    assert(!m.call, "without block second")
  ensure
    $VERBOSE = verbose_bak
  end

  def test_block_given_method_to_proc
    verbose_bak, $VERBOSE = $VERBOSE, nil
    bug8341 = '[Bug #8341]'
    m = method(:m_block_given?).to_proc
    assert(!m.call, "#{bug8341} without block")
    assert(m.call {}, "#{bug8341} with block")
    assert(!m.call, "#{bug8341} without block second")
  ensure
    $VERBOSE = verbose_bak
  end

  def test_block_persist_between_calls
    bug8341 = '[Bug #8341]'
    o = Object.new
    def o.m1(top=true)
      if top
        [block_given?, @m.call(false)]
      else
        block_given?
      end
    end
    m = o.method(:m1).to_proc
    o.instance_variable_set(:@m, m)
    assert_equal([true, false], m.call {}, "#{bug8341} nested with block")
    assert_equal([false, false], m.call, "#{bug8341} nested without block")
  end

  def test_curry_proc
    b = proc {|x, y, z| (x||0) + (y||0) + (z||0) }
    assert_equal(6, b.curry[1][2][3])
    assert_equal(6, b.curry[1, 2][3, 4])
    assert_equal(6, b.curry(5)[1][2][3][4][5])
    assert_equal(6, b.curry(5)[1, 2][3, 4][5])
    assert_equal(1, b.curry(1)[1])
  end

  def test_curry_proc_splat
    b = proc {|x, y, z, *w| (x||0) + (y||0) + (z||0) + w.inject(0, &:+) }
    assert_equal(6, b.curry[1][2][3])
    assert_equal(10, b.curry[1, 2][3, 4])
    assert_equal(15, b.curry(5)[1][2][3][4][5])
    assert_equal(15, b.curry(5)[1, 2][3, 4][5])
    assert_equal(1, b.curry(1)[1])
  end

  def test_curry_lambda
    b = lambda {|x, y, z| (x||0) + (y||0) + (z||0) }
    assert_equal(6, b.curry[1][2][3])
    assert_raise(ArgumentError) { b.curry[1, 2][3, 4] }
    assert_raise(ArgumentError) { b.curry(5) }
    assert_raise(ArgumentError) { b.curry(1) }
  end

  def test_curry_lambda_splat
    b = lambda {|x, y, z, *w| (x||0) + (y||0) + (z||0) + w.inject(0, &:+) }
    assert_equal(6, b.curry[1][2][3])
    assert_equal(10, b.curry[1, 2][3, 4])
    assert_equal(15, b.curry(5)[1][2][3][4][5])
    assert_equal(15, b.curry(5)[1, 2][3, 4][5])
    assert_raise(ArgumentError) { b.curry(1) }
  end

  def test_curry_no_arguments
    b = proc { :foo }
    assert_equal(:foo, b.curry[])
  end

  def test_curry_given_blocks
    b = lambda {|x, y, &blk| blk.call(x + y) }.curry
    b = assert_warning(/given block not used/) {b.call(2) { raise }}
    b = b.call(3) {|x| x + 4 }
    assert_equal(9, b)
  end

  # Not named test_curry_* so that test_curry_with_trace does not re-run it
  # under set_trace_func (which would be needlessly slow with GC.stress).
  def test_proc_curry_keeps_args_alive
    # The argument array passed down by `curry` must stay alive across the
    # inner call; otherwise GC may reclaim it while it is still read as argv
    # and crash with "try to mark T_NONE object". See the RB_GC_GUARD in `curry`.
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}", timeout: 60)
    begin;
      GC.stress = true
      l = ->(a, b, c) { a + b + c }
      30.times do
        l1 = l.curry.call(1)
        l2 = l1.curry.call(2)
        assert_equal(6, l2.curry.call(3))
        assert_equal(6, l1.curry.call(2, 3))
      end
    end;
  end

  def test_lambda?
    l = proc {}
    assert_equal(false, l.lambda?)
    assert_equal(false, l.curry.lambda?, '[ruby-core:24127]')
    assert_equal(false, proc(&l).lambda?)
    assert_equal(false, Proc.new(&l).lambda?)
    l = lambda {}
    assert_equal(true, l.lambda?)
    assert_equal(true, l.curry.lambda?, '[ruby-core:24127]')
    assert_equal(true, proc(&l).lambda?)
    assert_equal(true, lambda(&l).lambda?)
    assert_equal(true, Proc.new(&l).lambda?)
  end

  def helper_test_warn_lambda_with_passed_block &b
    lambda(&b)
  end

  def test_lambda_warning_pass_proc
    assert_raise(ArgumentError) do
      b = proc{}
      lambda(&b)
    end
  end

  def test_lambda_warning_pass_block
    assert_raise(ArgumentError) do
      helper_test_warn_lambda_with_passed_block{}
    end
  end

  def test_curry_ski_fib
    s = proc {|f, g, x| f[x][g[x]] }.curry
    k = proc {|x, y| x }.curry
    i = proc {|x| x }.curry

    fib = []
    inc = proc {|x| fib[-1] += 1; x }.curry
    ret = proc {|x| throw :end if fib.size > 10; fib << 0; x }.curry

    catch(:end) do
      s[
        s[s[i][i]][k[i]]
      ][
        k[inc]
      ][
        s[
          s[
            k[s]
          ][
            s[k[s[k[s]]]
          ][
            s[s[k[s]][s[k[s[k[ret]]]][s[k[s[i]]][k]]]][k]]
          ]
        ][
          k[s[k[s]][k]]
        ]
      ]
    end

    assert_equal(fib, [1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89])
  end

  def test_curry_passed_block
    a = lambda {|x, y, &b| b }
    b = a.curry[1]

    assert_not_nil(b.call(2){}, '[ruby-core:15551]: passed block to curried block')
  end

  def test_curry_instance_exec
    a = lambda { |x, y| [x + y, self] }
    b = a.curry.call(1)
    result = instance_exec 2, &b

    assert_equal(3, result[0])
    assert_equal(self, result[1])
  end

  def test_curry_optional_params
    obj = Object.new
    def obj.foo(a, b=42); end
    assert_raise(ArgumentError) { obj.method(:foo).to_proc.curry(3) }
    assert_raise(ArgumentError) { ->(a, b=42){}.curry(3) }
  end

  def test_dup_clone
    # iseq backed proc
    b = proc {|x| x + "bar" }
    class << b; attr_accessor :foo; end

    bd = b.dup
    assert_equal("foobar", bd.call("foo"))
    assert_raise(NoMethodError) { bd.foo = :foo }
    assert_raise(NoMethodError) { bd.foo }

    bc = b.clone
    assert_equal("foobar", bc.call("foo"))
    bc.foo = :foo
    assert_equal(:foo, bc.foo)

    # ifunc backed proc
    b = {foo: "bar"}.to_proc

    bd = b.dup
    assert_equal("bar", bd.call(:foo))

    bc = b.clone
    assert_equal("bar", bc.call(:foo))

    # symbol backed proc
    b = :to_s.to_proc

    bd = b.dup
    assert_equal("testing", bd.call(:testing))

    bc = b.clone
    assert_equal("testing", bc.call(:testing))
  end

  def test_dup_subclass
    c1 = Class.new(Proc)
    assert_equal c1, c1.new{}.dup.class, '[Bug #17545]'
    c1 = Class.new(Proc) {def initialize_dup(*) throw :initialize_dup; end}
    assert_throw(:initialize_dup) {c1.new{}.dup}
  end

  def test_dup_ifunc_proc_bug_20950
    assert_normal_exit(<<~RUBY, "[Bug #20950]")
      p = { a: 1 }.to_proc
      100.times do
        p = p.dup
        GC.start
        p.call
      rescue ArgumentError
      end
    RUBY
  end

  module RefinementsModule
    refine String do
      def shout = upcase + "!"
    end
    refine Integer do
      def tripled = self * 3
    end
  end

  def test_refined
    orig = ->(s) { s.shout }
    refined = orig.refined(RefinementsModule)
    assert_equal("HI!", refined.call("hi"))
    # the original Proc is unaffected
    assert_raise(NoMethodError) { orig.call("hi") }
    # idempotent: calling repeatedly keeps using the refinement
    assert_equal("HI!", refined.call("hi"))
  end

  def test_refined_nested_block
    orig = ->(a) { a.map { |s| s.shout } }
    refined = orig.refined(RefinementsModule)
    assert_equal(["A!", "B!"], refined.call(["a", "b"]))
    assert_raise(NoMethodError) { orig.call(["a"]) }
  end

  def test_refined_multiple_modules
    refined = ->(s, n) { "#{s.shout}#{n.tripled}" }.refined(RefinementsModule)
    assert_equal("A!6", refined.call("a", 2))
  end

  def test_refined_shares_environment
    counter = 0
    inc = -> { counter += 1 }
    refined = inc.refined(RefinementsModule)
    refined.call
    inc.call
    # the closure environment is shared with the original Proc
    assert_equal(2, counter)
  end

  def test_refined_via_yield
    refined = ->(s) { s.shout }.refined(RefinementsModule)
    result = [].tap {|a| [1, 2].each {|i| a << refined.call("x#{i}") } }
    assert_equal(["X1!", "X2!"], result)

    forwarded = []
    rr = ->(s) { forwarded << s.shout }.refined(RefinementsModule)
    %w[p q].each(&rr)
    assert_equal(["P!", "Q!"], forwarded)
  end

  def test_refined_via_c_call_paths
    refined = ->(s) { s.shout }.refined(RefinementsModule)
    # These reach the proc via the C invocation path (rb_vm_invoke_proc) rather
    # than the optimized opt_call, so the refinement cref must be carried there.
    assert_equal("A!", refined.send(:call, "a"))
    assert_equal("B!", refined.method(:call).call("b"))
    assert_equal("C!", Fiber.new(&refined).resume("c"))
    assert_equal("D!", Thread.new("d", &refined).value)
  end

  def test_refined_instance_eval
    refined = proc { self.shout }.refined(RefinementsModule)
    assert_equal("HI!", "hi".instance_eval(&refined))
    assert_equal("HI!", "hi".instance_exec(&refined))
    # the original Proc is still unaffected via instance_eval
    orig = proc { self.shout }
    assert_raise(NoMethodError) { "hi".instance_eval(&orig) }
  end

  def test_refined_module_eval
    refined = proc { "ok".shout }.refined(RefinementsModule)
    klass = Class.new
    assert_equal("OK!", klass.class_eval(&refined))
  end

  def test_refined_instance_eval_does_not_leak_refinements
    # instance_eval/class_eval gets its own copy of the refinements hash, so a
    # `using` inside must not mutate the cref shared by every derived proc.
    refined = proc { "ok".shout }.refined(RefinementsModule)
    Class.new.class_eval(&refined)
    # a second proc derived from the same source iseq still sees the refinement
    again = proc { "ok".shout }.refined(RefinementsModule)
    assert_equal("OK!", Class.new.class_eval(&again))
  end

  def test_refined_once_regexp
    # A /o (once) regexp literal interpolating a refined-method call must be
    # built under the refinement, and the copy's once cache is independent of
    # the source iseq's (which may be mid-flight or already completed).
    refined = ->(s) { /\A#{s.shout}\z/o }.refined(RefinementsModule)
    r1 = refined.call("ab")
    assert_equal('\AAB!\z', r1.source)
    # /o caches the first regexp on the copy's own once entry
    assert_same(r1, refined.call("zz"))
    # the original proc has no refinement, so building the regexp raises
    assert_raise(NoMethodError) { ->(s) { /\A#{s.shout}\z/o }.call("ab") }
  end

  def test_refined_preserved_by_dup
    refined = ->(s) { s.shout }.refined(RefinementsModule)
    # dup/clone copy the refinement cref (a hidden ivar) with the other ivars
    assert_equal("Z!", refined.dup.call("z"))
    assert_equal("Z!", refined.clone.call("z"))
  end

  def test_refined_no_arguments
    original = -> {}
    assert_same(original, original.refined)
  end

  def test_refined_errors
    assert_raise(TypeError) { ->(s) { s }.refined(42) }
    # non-iseq Procs are not supported
    assert_raise(ArgumentError) { :upcase.to_proc.refined(RefinementsModule) }
    assert_raise(ArgumentError) { method(:p).to_proc.refined(RefinementsModule) }
  end

  def test_refined_non_main_ractor
    assert_separately([], <<~'RUBY')
      Warning[:experimental] = false
      module M1; refine(String) { def shout = upcase + "!" }; end
      module M2; refine(String) { def shout = downcase }; end
      ractors = 10.times.map { |i|
        Ractor.new(i) { |i|
          ->(s) { s.shout }.refined(i.even? ? M1 : M2).call("Hi")
        }
      }
      values = ractors.map(&:value)
      assert_equal(["HI!", "hi"] * 5, values)
    RUBY
  end

  def test_refined_shareable_proc_across_ractors
    assert_separately([], <<~'RUBY')
      Warning[:experimental] = false
      module RefMod; refine(String) { def shout = upcase + "!" }; end
      module RefHolder
        # module body: self is shareable, as make_shareable requires
        PROC = Ractor.make_shareable(->(s) { s.shout })
      end
      orig = RefHolder::PROC
      # Store a memo in the main Ractor first, then refine the same shareable
      # proc in another Ractor: cross-Ractor reuse of the memo is legal
      # because the memoized cref's refinements table is frozen and shareable.
      assert_equal("HI!", orig.refined(RefMod).call("hi"))
      r = Ractor.new(orig) { |pr| pr.refined(RefMod).call("hi") }
      assert_equal("HI!", r.value)
      assert_equal("HI!", orig.refined(RefMod).call("hi"))
    RUBY
  end

  def test_refined_coverage
    assert_separately(%w[-rcoverage -rtempfile], <<~'RUBY')
      f = Tempfile.open(["refined_coverage", ".rb"])
      f.write(<<~'FIXTURE')
        module RefinedCoverageExt
          refine String do
            def shout = upcase + "!"
          end
        end
        REFINED_COVERAGE_PROC = ->(s) {
          a = s.length
          s.shout * a
        }
      FIXTURE
      f.close
      Coverage.start(lines: true)
      load f.path
      refined = REFINED_COVERAGE_PROC.refined(RefinedCoverageExt)
      assert_equal("HI!HI!", refined.call("hi"))
      lines = Coverage.result[f.path][:lines]
      assert_equal(1, lines[6], "line 7 (a = s.length) must be counted when run through the refined copy")
      assert_equal(1, lines[7], "line 8 (s.shout * a) must be counted when run through the refined copy")
    RUBY
  end

  def test_refined_using_in_body_rejected
    # The refinement set of a refined proc is fixed at refined() time: procs
    # derived from the same source and modules share the copied iseq (and its
    # refined call caches), so `using` inside the body would diverge one
    # proc's refinement set and poison the caches its siblings use.
    assert_separately([], <<~'RUBY')
      module M1; refine(String) { def shout = upcase + "!" }; end
      module M2; refine(String) { def whisper = downcase + "..." }; end
      msg = /using is not permitted in a proc with refinements/
      r = proc { using M2 }.refined(M1)
      assert_raise_with_message(RuntimeError, msg) { r.call }
      # through module_eval (Module#using) as well
      e = proc { using M2 }.refined(M1)
      assert_raise_with_message(RuntimeError, msg) { Module.new.module_eval(&e) }
      # in a class body or a nested block inside the refined proc
      c = proc { class ::RefinedUsingTmp; using M2; end }.refined(M1)
      assert_raise_with_message(RuntimeError, msg) { c.call }
      n = proc { -> { using M2 }.call }.refined(M1)
      assert_raise_with_message(RuntimeError, msg) { n.call }
      # plain procs are unaffected
      assert_equal("ok...", Module.new.module_eval(&proc { using M2; "ok".whisper }))
      # and the refined proc itself still works
      assert_equal("OK!", proc { "ok".shout }.refined(M1).call)
    RUBY
  end

  def test_refined_rejected_by_define_method
    # A bmethod is invoked against its method entry, not the proc's refinement
    # cref, so defining a method from a refined proc would silently drop
    # the refinements; it is rejected instead.
    refined = ->(s) { s.shout }.refined(RefinementsModule)
    assert_raise(ArgumentError) { Class.new { define_method(:m, refined) } }
    assert_raise(ArgumentError) { Class.new { define_method(:m, &refined) } }
    assert_raise(ArgumentError) { Object.new.define_singleton_method(:m, refined) }
  end

  # Each refinement module refines only one class so the nested test below can
  # tell apart the refinement added on the inner Proc (String) from the one
  # inherited from the enclosing refined Proc (Integer).
  module RefinementsStringOnly
    refine String do
      def shout = upcase + "!"
    end
  end

  module RefinementsIntegerOnly
    refine Integer do
      def doubled = self * 2
    end
  end

  def test_refined_nested_proc
    result = -> {
      inner = ->(s, n) { [s.shout, n.doubled] }
      inner.refined(RefinementsStringOnly).call("hi", 3)
    }.refined(RefinementsIntegerOnly).call
    # RefinementsStringOnly is added on the inner copy; RefinementsIntegerOnly
    # is inherited from the enclosing refined Proc.
    assert_equal(["HI!", 6], result)

    # define_method from such a nested Proc is allowed (it is not the
    # refined result itself).
    assert_nothing_raised do
      -> { Class.new { define_method(:m, ->(s) { s }) } }.refined(RefinementsIntegerOnly).call
    end
  end

  def test_refined_chain
    refined = ->(s, n) { [s.shout, n.doubled] }.refined(RefinementsStringOnly).refined(RefinementsIntegerOnly)
    assert_equal(["HI!", 6], refined.call("hi", 3))

    refined2 = ->(s) { s.shout }.refined(RefinementsModule).refined(RefinementsModule2)
    assert_equal("?", refined2.call("hi"))
    refined3 = ->(s) { s.shout }.refined(RefinementsModule2).refined(RefinementsModule)
    assert_equal("HI!", refined3.call("hi"))
  end

  def test_refined_gc
    assert_normal_exit(<<~RUBY)
      module M
        refine(String) { def shout = upcase + "!" }
      end
      procs = 100.times.map { |i| ->(s) { s.shout } .refined(M) }
      GC.start
      GC.compact rescue nil
      procs.each { |pr| raise "bad" unless pr.call("a") == "A!" }
    RUBY
  end

  def test_refined_gc_stress
    # Under GC.stress, the memo store allocates its module array while the memo
    # is reachable from the iseq; a GC during that allocation must not observe a
    # half-initialized memo (argc set but mods not yet allocated).  Alternating
    # module sets keeps missing the memo so each call re-runs the store; one
    # small iseq keeps it cheap enough for slow CI runners.
    assert_normal_exit(<<~RUBY)
      module M1; refine(String) { def shout = upcase + "!" }; end
      module M2; refine(String) { def shout = downcase }; end
      orig = ->(s) { s.shout }
      r = nil
      GC.stress = true
      6.times { |i| r = orig.refined(i.even? ? M1 : M2) }
      GC.stress = false
      raise "bad" unless r.call("Hi") == "hi"
    RUBY
  end

  def test_refined_iseq_to_binary
    # A block iseq that has memoized copies must still serialize cleanly
    # (the memo lives outside the iseq).
    assert_separately([], <<~'RUBY')
      module M
        refine(String) { def shout = upcase + "!" }
      end
      src = 'x = ->(s) { s.shout }; x.refined(M).call("hi")'
      iseq = RubyVM::InstructionSequence.compile(src)
      eval(src) # runs refined, setting the memo on the block iseq
      bin = iseq.to_binary
      loaded = RubyVM::InstructionSequence.load_from_binary(bin)
      assert_equal("HI!", loaded.eval)
    RUBY
  end

  module RefinementsModule2
    refine String do
      def shout = "?"
    end
  end

  def test_refined_memoized
    orig = ->(s) { s.shout }
    # Repeating the same (proc, modules) reuses the cached copy but stays correct.
    assert_equal("HI!", orig.refined(RefinementsModule).call("hi"))
    assert_equal("HI!", orig.refined(RefinementsModule).call("hi"))
    # A different module set must not return the previously cached copy.
    assert_equal("?", orig.refined(RefinementsModule2).call("hi"))
    # ...and switching back is still correct.
    assert_equal("HI!", orig.refined(RefinementsModule).call("hi"))
  end

  def test_refined_ruby2_keywords_memo
    # Proc#ruby2_keywords marks the shared block iseq, possibly after a copy
    # was memoized.  The stale memo is rebuilt (with a warning naming the
    # cause) rather than reused or mutated: the new proc delegates keywords
    # like its source, while procs built before the mark keep their
    # creation-time behavior.
    assert_separately([], <<~'RUBY')
      module M; refine(String) { def shout = upcase + "!" }; end
      Warning[:performance] = true
      $warned = []
      def Warning.warn(msg, category: nil) = $warned << msg
      target = ->(a, k: nil) { [a, k] }
      pr = proc { |*args| target.call(*args) }
      q1 = pr.refined(M) # memoize a copy before the mark
      pr.ruby2_keywords
      assert_equal([1, 2], pr.call(1, k: 2))
      q2 = pr.refined(M)
      assert_equal([1, 2], q2.call(1, k: 2))
      assert_equal(1, $warned.grep(/ruby2_keywords/).size)
      # the copy made before the mark is not retroactively changed
      assert_raise(ArgumentError) { q1.call(1, k: 2) }
      # the rebuilt memo is hit from now on; no further warnings
      assert_equal([1, 2], pr.refined(M).call(1, k: 2))
      assert_equal(1, $warned.grep(/ruby2_keywords/).size)
    RUBY
  end

  def test_refined_memo_distinct_environments
    # Procs sharing the same block iseq but capturing different closure
    # environments hit the same memo entry (env is not part of the key), yet each
    # result must keep its own environment.
    factory = ->(tag) { ->(s) { "#{tag}:#{s.shout}" } }
    p1 = factory.call("A")
    p2 = factory.call("B")
    r1 = p1.refined(RefinementsModule)
    r2 = p2.refined(RefinementsModule)
    assert_equal("A:X!", r1.call("x"))
    assert_equal("B:Y!", r2.call("y"))
    # the original closures still see their own captured tag too
    assert_equal("A:X!", r1.call("x"))
  end

  def test_refined_memo_avoids_recopy
    orig = ->(s) { s.shout }
    orig.refined(RefinementsModule) # warm the memo
    GC.disable
    begin
      before = GC.stat(:total_allocated_objects)
      100.times { orig.refined(RefinementsModule) }
      hits = GC.stat(:total_allocated_objects) - before

      before = GC.stat(:total_allocated_objects)
      100.times do |i|
        orig.refined(i.even? ? RefinementsModule : RefinementsModule2)
      end
      misses = GC.stat(:total_allocated_objects) - before
    ensure
      GC.enable
    end
    # Memo hits must allocate far less than recomputing the iseq copy each time.
    assert_operator(misses, :>, hits * 2,
                    "expected memo hits (#{hits}) to allocate much less than misses (#{misses})")
  end

  def test_refined_memo_different_modules_warning
    assert_separately([], <<~'RUBY')
      module M1; refine(String) { def shout = "1" }; end
      module M2; refine(String) { def shout = "2" }; end
      Warning[:performance] = true
      $warned = []
      def Warning.warn(msg, category: nil) = $warned << msg
      pr = ->(s) { s.shout }
      pr.refined(M1)
      pr.refined(M2) # evicts the M1 entry
      assert_equal(1, $warned.grep(/different modules/).size)
    RUBY
  end

  def test_refined_chain_warning
    assert_separately([], <<~'RUBY')
      module M1; refine(String) { def shout = "1" }; end
      module M2; refine(String) { def shout = "2" }; end
      Warning[:performance] = true
      $warned = []
      def Warning.warn(msg, category: nil) = $warned << msg
      pr = ->(s) { s.shout }
      pr.refined(M1).refined(M2)
      assert_equal(1, $warned.grep(/already refined/).size)
    RUBY
  end

  def test_refined_memo_survives_gc
    assert_separately([], <<~'RUBY')
      module M; refine(String) { def shout = upcase + "!" }; end
      pr = ->(s) { [1].each { }; s.shout }
      # the memo lives as long as its source iseq, so the copy stays
      # memoized even when no refined proc survives the GC
      pr.refined(M)
      GC.start
      assert_equal("HI!", pr.refined(M).call("hi"))
      rp = pr.refined(M)
      GC.start
      assert_equal("HI!", rp.call("hi"))
      assert_equal("HI!", pr.refined(M).call("hi"))
    RUBY
  end

  def test_refined_memo_gc_compact
    assert_separately([], <<~'RUBY')
      module M; refine(String) { def shout = upcase + "!" }; end
      pr = ->(s) { [1].each { }; s.shout }
      rp = pr.refined(M)
      begin
        GC.compact
      rescue NotImplementedError
        omit "GC compaction not supported on this platform"
      end
      assert_equal("HI!", rp.call("hi"))
      assert_equal("HI!", pr.refined(M).call("hi"))
    RUBY
  end

  def test_refined_memo_survives_compaction
    # the memo is a hidden identity Hash: its keys (source iseqs) are pinned,
    # while its values (copied iseqs, crefs) move and must be updated correctly
    assert_separately([], <<~'RUBY')
      omit "compaction unsupported" unless GC.respond_to?(:verify_compaction_references)
      module M; refine(String) { def shout = upcase + "!" }; end
      blocks = eval("[" + (["->(s) { s.shout }"] * 500).join(",\n") + "]")
      kept = blocks.map { |b| b.refined(M) }
      begin
        GC.verify_compaction_references(expand_heap: true, toward: :empty)
      rescue NotImplementedError
        omit "compaction unsupported on this platform"
      end
      kept.each { |r| assert_equal("HI!", r.call("hi")) }
      blocks.each { |b| assert_equal("HI!", b.refined(M).call("hi")) }
      GC.compact
      blocks.each { |b| assert_equal("HI!", b.refined(M).call("hi")) }
    RUBY
  end

  def test_refined_rescue_ensure
    # exercises the copied catch table and shared rescue local table
    refined = ->(s) {
      r = nil
      begin
        r = s.shout
      rescue NoMethodError
        r = "rescued"
      ensure
        r = "#{r}."
      end
      r
    }.refined(RefinementsModule)
    assert_equal("YO!.", refined.call("yo"))
  end

  def test_refined_def_in_block
    # a literal def inside the block creates a nested method iseq whose
    # local_iseq is itself (in-subtree); the copy must rebuild it.
    # Specified behavior: like a def inside a `using` scope, a method defined
    # inside the block sees the refinements (the def captures the block's
    # cref), so the refinement also applies when the method is called later.
    refined = ->(s) {
      o = Object.new
      def o.m = "hi".shout
      [s.shout, o.m]
    }.refined(RefinementsModule)
    assert_equal(["YO!", "HI!"], refined.call("yo"))
  end

  def test_refined_keyword_and_optional_args
    refined = ->(a, b = "z", c:, d: "w") {
      [a, b, c, d].map(&:shout).join
    }.refined(RefinementsModule)
    assert_equal("A!Z!C!W!", refined.call("a", c: "c"))
    assert_equal("A!B!C!D!", refined.call("a", "b", c: "c", d: "d"))
  end

  def test_refined_case_when_literal
    # literal when-clauses compile to a CDHASH operand that must round-trip
    refined = ->(s) {
      case s.shout
      when "A!" then 1
      when "B!" then 2
      else 0
      end
    }.refined(RefinementsModule)
    assert_equal(1, refined.call("a"))
    assert_equal(2, refined.call("b"))
    assert_equal(0, refined.call("c"))
  end

  def test_refined_flip_flop
    # flip-flop allocates a special-variable slot keyed off the local iseq;
    # the copy must run its own flip state independent of the original
    body = ->(arr) {
      out = []
      arr.each { |i| out << i if (i == 2)..(i == 4) }
      out
    }
    refined = body.refined(RefinementsModule)
    assert_equal([2, 3, 4], refined.call([1, 2, 3, 4, 5]))
    # a second call starts from a fresh flip state
    assert_equal([2, 3, 4], refined.call([1, 2, 3, 4, 5]))
  end

  def test_refined_preserves_location_and_parameters
    orig = ->(a, b = 1, *c, d:, **e, &f) { a }
    refined = orig.refined(RefinementsModule)
    assert_equal(orig.source_location, refined.source_location)
    assert_equal(orig.parameters, refined.parameters)
    assert_equal(orig.arity, refined.arity)
  end

  module RefinementsOperators
    refine Integer do
      def +(other) = "plus(#{self},#{other})"
      def <(other) = "lt"
    end
    refine Array do
      def [](i) = "at#{i}"
    end
  end

  def test_refined_operators
    # Specialized instructions (opt_plus, opt_lt, opt_aref, ...) must honor the
    # refinement on the copy without leaking it into the original Proc.
    refined = ->(a, b) { [a + b, a < b] }.refined(RefinementsOperators)
    assert_equal(["plus(1,2)", "lt"], refined.call(1, 2))
    aref = ->(a) { a[0] }.refined(RefinementsOperators)
    assert_equal("at0", aref.call([9]))
    # the original Procs keep using the builtin operators
    assert_equal(3, ->(a, b) { a + b }.call(1, 2))
  end

  def test_refined_preserves_lambda
    # The copy must keep the receiver's lambda/proc nature, including a lambda's
    # strict argument checking.
    lam = ->(a, b) { [a, b] }.refined(RefinementsModule)
    assert_equal(true, lam.lambda?)
    assert_raise(ArgumentError) { lam.call(1) }
    pr = proc { |a, b| [a, b] }.refined(RefinementsModule)
    assert_equal(false, pr.lambda?)
    # proc argument handling fills missing parameters with nil instead of raising
    assert_equal([1, nil], pr.call(1))
  end

  def test_refined_preserved_by_clone
    refined = ->(s) { s.shout }.refined(RefinementsModule)
    assert_equal("Z!", refined.clone.call("z"))
  end

  def test_refined_module_precedence
    # When several modules refine the same method, the last one wins, matching
    # the precedence of nested `using`.
    body = ->(s) { s.shout }
    assert_equal("?", body.refined(RefinementsModule, RefinementsModule2).call("Hi"))
    assert_equal("HI!", body.refined(RefinementsModule2, RefinementsModule).call("Hi"))
  end

  class RefinementsSuperBase
    def greet = "base"
  end

  module RefinementsSuperModule
    refine RefinementsSuperBase do
      def greet = "ref-" + super
    end
  end

  def test_refined_super
    # A refined method may call super to reach the method it refines.
    refined = ->(o) { o.greet }.refined(RefinementsSuperModule)
    assert_equal("ref-base", refined.call(RefinementsSuperBase.new))
  end

  def test_refined_tracepoint
    # Line events fire on the copied iseq just like on the original.
    src = "->(s) {\n  x = s.shout\n  x\n}"
    refined = eval(src, binding, "wr_trace_eval").refined(RefinementsModule)
    lines = []
    tp = TracePoint.new(:line) { |t| lines << t.lineno if t.path == "wr_trace_eval" }
    result = tp.enable { refined.call("hi") }
    assert_equal("HI!", result)
    assert_equal([2, 3], lines)
  end

  def test_refined_recursion_sees_refinements
    # The copy shares the source Proc's environment, so a recursive call through
    # the captured local reaches the refined Proc and keeps the refinements.
    fact = nil
    fact = ->(s) { s.empty? ? "" : s[0].shout + fact.call(s[1..]) }
              .refined(RefinementsModule)
    assert_equal("A!B!C!", fact.call("abc"))
  end

  def test_clone_subclass
    c1 = Class.new(Proc)
    assert_equal c1, c1.new{}.clone.class, '[Bug #17545]'
    c1 = Class.new(Proc) {def initialize_clone(*) throw :initialize_clone; end}
    assert_throw(:initialize_clone) {c1.new{}.clone}
  end

  def test_binding
    b = proc {|x, y, z| proc {}.binding }.call(1, 2, 3)
    class << b; attr_accessor :foo; end

    bd = b.dup
    assert_equal([1, 2, 3], bd.eval("[x, y, z]"))
    assert_raise(NoMethodError) { bd.foo = :foo }
    assert_raise(NoMethodError) { bd.foo }

    bc = b.clone
    assert_equal([1, 2, 3], bc.eval("[x, y, z]"))
    bc.foo = :foo
    assert_equal(:foo, bc.foo)

    b = nil
    1.times { x, y, z = 1, 2, 3; [x,y,z]; b = binding }
    assert_equal([1, 2, 3], b.eval("[x, y, z]"))
  end

  def test_binding_source_location
    b, expected_location = binding, [__FILE__, __LINE__]
    assert_equal(expected_location, b.source_location)

    file, lineno = method(:source_location_test).to_proc.binding.source_location
    assert_match(/^#{ Regexp.quote(__FILE__) }$/, file)
    assert_equal(@@line_of_source_location_test, lineno, 'Bug #2427')
  end

  def test_binding_error_unless_ruby_frame
    define_singleton_method :binding_from_c!, method(:binding).to_proc >> ->(bndg) {bndg}
    assert_raise(RuntimeError) { binding_from_c! }
  end

  def test_proc_lambda
    assert_raise(ArgumentError) { proc }
    assert_raise(ArgumentError) { assert_warn(/deprecated/) {lambda} }

    o = Object.new
    def o.foo
      b = nil
      1.times { b = lambda }
      b
    end
    assert_raise(ArgumentError) do
      assert_deprecated_warning {o.foo { :foo }}.call
    end

    def o.bar(&b)
      b = nil
      1.times { b = lambda }
      b
    end
    assert_raise(ArgumentError) do
      assert_deprecated_warning {o.bar { :foo }}.call
    end
  end

  def test_arity2
    assert_equal(0, method(:proc).to_proc.arity)
    assert_equal(-1, proc {}.curry.arity)

    c = Class.new
    c.class_eval { attr_accessor :foo }
    assert_equal(1, c.new.method(:foo=).to_proc.arity)
  end

  def test_proc_location
    t = Thread.new { sleep }
    assert_raise(ThreadError) { t.instance_eval { initialize { } } }
    t.kill
    t.join
  end

  def test_to_proc
    b = proc { :foo }
    assert_equal(:foo, b.to_proc.call)
  end

  def test_localjump_error
    o = o = Object.new
    def foo; yield; end
    exc = foo rescue $!
    assert_nil(exc.exit_value)
    assert_equal(:noreason, exc.reason)
  end

  def test_curry_binding
    assert_raise(ArgumentError) { proc {}.curry.binding }
  end

  def test_proc_args_plain
    pr = proc {|a,b,c,d,e|
      [a,b,c,d,e]
    }
    assert_equal [nil,nil,nil,nil,nil],  pr.call()
    assert_equal [1,nil,nil,nil,nil],  pr.call(1)
    assert_equal [1,2,nil,nil,nil],  pr.call(1,2)
    assert_equal [1,2,3,nil,nil],  pr.call(1,2,3)
    assert_equal [1,2,3,4,nil],  pr.call(1,2,3,4)
    assert_equal [1,2,3,4,5],  pr.call(1,2,3,4,5)
    assert_equal [1,2,3,4,5],  pr.call(1,2,3,4,5,6)

    assert_equal [nil,nil,nil,nil,nil],  pr.call([])
    assert_equal [1,nil,nil,nil,nil],  pr.call([1])
    assert_equal [1,2,nil,nil,nil],  pr.call([1,2])
    assert_equal [1,2,3,nil,nil],  pr.call([1,2,3])
    assert_equal [1,2,3,4,nil],  pr.call([1,2,3,4])
    assert_equal [1,2,3,4,5],  pr.call([1,2,3,4,5])
    assert_equal [1,2,3,4,5],  pr.call([1,2,3,4,5,6])

    r = proc{|a| a}.call([1,2,3])
    assert_equal [1,2,3], r

    r = proc{|a,| a}.call([1,2,3])
    assert_equal 1, r

    r = proc{|a,| a}.call([])
    assert_equal nil, r
  end


  def test_proc_args_rest
    pr = proc {|a,b,c,*d|
      [a,b,c,d]
    }
    assert_equal [nil,nil,nil,[]],  pr.call()
    assert_equal [1,nil,nil,[]],  pr.call(1)
    assert_equal [1,2,nil,[]],  pr.call(1,2)
    assert_equal [1,2,3,[]],  pr.call(1,2,3)
    assert_equal [1,2,3,[4]], pr.call(1,2,3,4)
    assert_equal [1,2,3,[4,5]], pr.call(1,2,3,4,5)
    assert_equal [1,2,3,[4,5,6]], pr.call(1,2,3,4,5,6)

    assert_equal [nil,nil,nil,[]],  pr.call([])
    assert_equal [1,nil,nil,[]],  pr.call([1])
    assert_equal [1,2,nil,[]],  pr.call([1,2])
    assert_equal [1,2,3,[]],  pr.call([1,2,3])
    assert_equal [1,2,3,[4]], pr.call([1,2,3,4])
    assert_equal [1,2,3,[4,5]], pr.call([1,2,3,4,5])
    assert_equal [1,2,3,[4,5,6]], pr.call([1,2,3,4,5,6])

    r = proc{|*a| a}.call([1,2,3])
    assert_equal [[1,2,3]], r
  end

  def test_proc_args_pos_rest_post
    pr = proc {|a,b,*c,d,e|
      [a,b,c,d,e]
    }
    assert_equal [nil, nil, [], nil, nil], pr.call()
    assert_equal [1, nil, [], nil, nil], pr.call(1)
    assert_equal [1, 2, [], nil, nil], pr.call(1,2)
    assert_equal [1, 2, [], 3, nil], pr.call(1,2,3)
    assert_equal [1, 2, [], 3, 4], pr.call(1,2,3,4)
    assert_equal [1, 2, [3], 4, 5], pr.call(1,2,3,4,5)
    assert_equal [1, 2, [3, 4], 5, 6], pr.call(1,2,3,4,5,6)
    assert_equal [1, 2, [3, 4, 5], 6,7], pr.call(1,2,3,4,5,6,7)

    assert_equal [nil, nil, [], nil, nil], pr.call([])
    assert_equal [1, nil, [], nil, nil], pr.call([1])
    assert_equal [1, 2, [], nil, nil], pr.call([1,2])
    assert_equal [1, 2, [], 3, nil], pr.call([1,2,3])
    assert_equal [1, 2, [], 3, 4], pr.call([1,2,3,4])
    assert_equal [1, 2, [3], 4, 5], pr.call([1,2,3,4,5])
    assert_equal [1, 2, [3, 4], 5, 6], pr.call([1,2,3,4,5,6])
    assert_equal [1, 2, [3, 4, 5], 6,7], pr.call([1,2,3,4,5,6,7])
  end

  def test_proc_args_rest_post
    pr = proc {|*a,b,c|
      [a,b,c]
    }
    assert_equal [[], nil, nil], pr.call()
    assert_equal [[], 1, nil], pr.call(1)
    assert_equal [[], 1, 2], pr.call(1,2)
    assert_equal [[1], 2, 3], pr.call(1,2,3)
    assert_equal [[1, 2], 3, 4], pr.call(1,2,3,4)
    assert_equal [[1, 2, 3], 4, 5], pr.call(1,2,3,4,5)
    assert_equal [[1, 2, 3, 4], 5, 6], pr.call(1,2,3,4,5,6)
    assert_equal [[1, 2, 3, 4, 5], 6,7], pr.call(1,2,3,4,5,6,7)

    assert_equal [[], nil, nil], pr.call([])
    assert_equal [[], 1, nil], pr.call([1])
    assert_equal [[], 1, 2], pr.call([1,2])
    assert_equal [[1], 2, 3], pr.call([1,2,3])
    assert_equal [[1, 2], 3, 4], pr.call([1,2,3,4])
    assert_equal [[1, 2, 3], 4, 5], pr.call([1,2,3,4,5])
    assert_equal [[1, 2, 3, 4], 5, 6], pr.call([1,2,3,4,5,6])
    assert_equal [[1, 2, 3, 4, 5], 6,7], pr.call([1,2,3,4,5,6,7])
  end

  def test_proc_args_pos_opt
    pr = proc {|a,b,c=:c|
      [a,b,c]
    }
    assert_equal [nil, nil, :c], pr.call()
    assert_equal [1, nil, :c], pr.call(1)
    assert_equal [1, 2, :c], pr.call(1,2)
    assert_equal [1, 2, 3], pr.call(1,2,3)
    assert_equal [1, 2, 3], pr.call(1,2,3,4)
    assert_equal [1, 2, 3], pr.call(1,2,3,4,5)
    assert_equal [1, 2, 3], pr.call(1,2,3,4,5,6)

    assert_equal [nil, nil, :c], pr.call([])
    assert_equal [1, nil, :c], pr.call([1])
    assert_equal [1, 2, :c], pr.call([1,2])
    assert_equal [1, 2, 3], pr.call([1,2,3])
    assert_equal [1, 2, 3], pr.call([1,2,3,4])
    assert_equal [1, 2, 3], pr.call([1,2,3,4,5])
    assert_equal [1, 2, 3], pr.call([1,2,3,4,5,6])
  end

  def test_proc_args_opt
    pr = proc {|a=:a,b=:b,c=:c|
      [a,b,c]
    }
    assert_equal [:a, :b, :c], pr.call()
    assert_equal [1, :b, :c], pr.call(1)
    assert_equal [1, 2, :c], pr.call(1,2)
    assert_equal [1, 2, 3], pr.call(1,2,3)
    assert_equal [1, 2, 3], pr.call(1,2,3,4)
    assert_equal [1, 2, 3], pr.call(1,2,3,4,5)
    assert_equal [1, 2, 3], pr.call(1,2,3,4,5,6)

    assert_equal [:a, :b, :c], pr.call([])
    assert_equal [1, :b, :c], pr.call([1])
    assert_equal [1, 2, :c], pr.call([1,2])
    assert_equal [1, 2, 3], pr.call([1,2,3])
    assert_equal [1, 2, 3], pr.call([1,2,3,4])
    assert_equal [1, 2, 3], pr.call([1,2,3,4,5])
    assert_equal [1, 2, 3], pr.call([1,2,3,4,5,6])
  end

  def test_proc_args_opt_single
    bug7621 = '[ruby-dev:46801]'
    pr = proc {|a=:a|
      a
    }
    assert_equal :a, pr.call()
    assert_equal 1, pr.call(1)
    assert_equal 1, pr.call(1,2)

    assert_equal [], pr.call([]), bug7621
    assert_equal [1], pr.call([1]), bug7621
    assert_equal [1, 2], pr.call([1,2]), bug7621
    assert_equal [1, 2, 3], pr.call([1,2,3]), bug7621
    assert_equal [1, 2, 3, 4], pr.call([1,2,3,4]), bug7621
  end

  def test_proc_args_pos_opt_post
    pr = proc {|a,b,c=:c,d,e|
      [a,b,c,d,e]
    }
    assert_equal [nil, nil, :c, nil, nil], pr.call()
    assert_equal [1, nil, :c, nil, nil], pr.call(1)
    assert_equal [1, 2, :c, nil, nil], pr.call(1,2)
    assert_equal [1, 2, :c, 3, nil], pr.call(1,2,3)
    assert_equal [1, 2, :c, 3, 4], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, 4, 5], pr.call(1,2,3,4,5)
    assert_equal [1, 2, 3, 4, 5], pr.call(1,2,3,4,5,6)

    assert_equal [nil, nil, :c, nil, nil], pr.call([])
    assert_equal [1, nil, :c, nil, nil], pr.call([1])
    assert_equal [1, 2, :c, nil, nil], pr.call([1,2])
    assert_equal [1, 2, :c, 3, nil], pr.call([1,2,3])
    assert_equal [1, 2, :c, 3, 4], pr.call([1,2,3,4])
    assert_equal [1, 2, 3, 4, 5], pr.call([1,2,3,4,5])
    assert_equal [1, 2, 3, 4, 5], pr.call([1,2,3,4,5,6])
  end

  def test_proc_args_opt_post
    pr = proc {|a=:a,b=:b,c=:c,d,e|
      [a,b,c,d,e]
    }
    assert_equal [:a, :b, :c, nil, nil], pr.call()
    assert_equal [:a, :b, :c, 1, nil], pr.call(1)
    assert_equal [:a, :b, :c, 1, 2], pr.call(1,2)
    assert_equal [1, :b, :c, 2, 3], pr.call(1,2,3)
    assert_equal [1, 2, :c, 3, 4], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, 4, 5], pr.call(1,2,3,4,5)
    assert_equal [1, 2, 3, 4, 5], pr.call(1,2,3,4,5,6)

    assert_equal [:a, :b, :c, nil, nil], pr.call([])
    assert_equal [:a, :b, :c, 1, nil], pr.call([1])
    assert_equal [:a, :b, :c, 1, 2], pr.call([1,2])
    assert_equal [1, :b, :c, 2, 3], pr.call([1,2,3])
    assert_equal [1, 2, :c, 3, 4], pr.call([1,2,3,4])
    assert_equal [1, 2, 3, 4, 5], pr.call([1,2,3,4,5])
    assert_equal [1, 2, 3, 4, 5], pr.call([1,2,3,4,5,6])
  end

  def test_proc_args_pos_opt_rest
    pr = proc {|a,b,c=:c,*d|
      [a,b,c,d]
    }
    assert_equal [nil, nil, :c, []], pr.call()
    assert_equal [1, nil, :c, []], pr.call(1)
    assert_equal [1, 2, :c, []], pr.call(1,2)
    assert_equal [1, 2, 3, []], pr.call(1,2,3)
    assert_equal [1, 2, 3, [4]], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, [4, 5]], pr.call(1,2,3,4,5)

    assert_equal [nil, nil, :c, []], pr.call([])
    assert_equal [1, nil, :c, []], pr.call([1])
    assert_equal [1, 2, :c, []], pr.call([1,2])
    assert_equal [1, 2, 3, []], pr.call([1,2,3])
    assert_equal [1, 2, 3, [4]], pr.call([1,2,3,4])
    assert_equal [1, 2, 3, [4, 5]], pr.call([1,2,3,4,5])
  end

  def test_proc_args_opt_rest
    pr = proc {|a=:a,b=:b,c=:c,*d|
      [a,b,c,d]
    }
    assert_equal [:a, :b, :c, []], pr.call()
    assert_equal [1, :b, :c, []], pr.call(1)
    assert_equal [1, 2, :c, []], pr.call(1,2)
    assert_equal [1, 2, 3, []], pr.call(1,2,3)
    assert_equal [1, 2, 3, [4]], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, [4, 5]], pr.call(1,2,3,4,5)

    assert_equal [:a, :b, :c, []], pr.call([])
    assert_equal [1, :b, :c, []], pr.call([1])
    assert_equal [1, 2, :c, []], pr.call([1,2])
    assert_equal [1, 2, 3, []], pr.call([1,2,3])
    assert_equal [1, 2, 3, [4]], pr.call([1,2,3,4])
    assert_equal [1, 2, 3, [4, 5]], pr.call([1,2,3,4,5])
  end

  def test_proc_args_pos_opt_rest_post
    pr = proc {|a,b,c=:c,*d,e|
      [a,b,c,d,e]
    }
    assert_equal [nil, nil, :c, [], nil], pr.call()
    assert_equal [1, nil, :c, [], nil], pr.call(1)
    assert_equal [1, 2, :c, [], nil], pr.call(1,2)
    assert_equal [1, 2, :c, [], 3], pr.call(1,2,3)
    assert_equal [1, 2, 3, [], 4], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, [4], 5], pr.call(1,2,3,4,5)
    assert_equal [1, 2, 3, [4,5], 6], pr.call(1,2,3,4,5,6)

    assert_equal [nil, nil, :c, [], nil], pr.call([])
    assert_equal [1, nil, :c, [], nil], pr.call([1])
    assert_equal [1, 2, :c, [], nil], pr.call([1,2])
    assert_equal [1, 2, :c, [], 3], pr.call([1,2,3])
    assert_equal [1, 2, 3, [], 4], pr.call([1,2,3,4])
    assert_equal [1, 2, 3, [4], 5], pr.call([1,2,3,4,5])
    assert_equal [1, 2, 3, [4,5], 6], pr.call([1,2,3,4,5,6])
  end

  def test_proc_args_opt_rest_post
    pr = proc {|a=:a,b=:b,c=:c,*d,e|
      [a,b,c,d,e]
    }
    assert_equal [:a, :b, :c, [], nil], pr.call()
    assert_equal [:a, :b, :c, [], 1], pr.call(1)
    assert_equal [1, :b, :c, [], 2], pr.call(1,2)
    assert_equal [1, 2, :c, [], 3], pr.call(1,2,3)
    assert_equal [1, 2, 3, [], 4], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, [4], 5], pr.call(1,2,3,4,5)
    assert_equal [1, 2, 3, [4,5], 6], pr.call(1,2,3,4,5,6)

    assert_equal [:a, :b, :c, [], nil], pr.call([])
    assert_equal [:a, :b, :c, [], 1], pr.call([1])
    assert_equal [1, :b, :c, [], 2], pr.call([1,2])
    assert_equal [1, 2, :c, [], 3], pr.call([1,2,3])
    assert_equal [1, 2, 3, [], 4], pr.call([1,2,3,4])
    assert_equal [1, 2, 3, [4], 5], pr.call([1,2,3,4,5])
    assert_equal [1, 2, 3, [4,5], 6], pr.call([1,2,3,4,5,6])
  end

  def test_proc_args_pos_block
    pr = proc {|a,b,&c|
      [a, b, c.class, c&&c.call(:x)]
    }
    assert_equal [nil, nil, NilClass, nil], pr.call()
    assert_equal [1, nil, NilClass, nil], pr.call(1)
    assert_equal [1, 2, NilClass, nil], pr.call(1,2)
    assert_equal [1, 2, NilClass, nil], pr.call(1,2,3)
    assert_equal [1, 2, NilClass, nil], pr.call(1,2,3,4)

    assert_equal [nil, nil, NilClass, nil], pr.call([])
    assert_equal [1, nil, NilClass, nil], pr.call([1])
    assert_equal [1, 2, NilClass, nil], pr.call([1,2])
    assert_equal [1, 2, NilClass, nil], pr.call([1,2,3])
    assert_equal [1, 2, NilClass, nil], pr.call([1,2,3,4])

    assert_equal [nil, nil, Proc, :proc], (pr.call(){ :proc })
    assert_equal [1, nil, Proc, :proc], (pr.call(1){ :proc })
    assert_equal [1, 2, Proc, :proc], (pr.call(1, 2){ :proc })
    assert_equal [1, 2, Proc, :proc], (pr.call(1, 2, 3){ :proc })
    assert_equal [1, 2, Proc, :proc], (pr.call(1, 2, 3, 4){ :proc })

    assert_equal [nil, nil, Proc, :x], (pr.call(){|x| x})
    assert_equal [1, nil, Proc, :x], (pr.call(1){|x| x})
    assert_equal [1, 2, Proc, :x], (pr.call(1, 2){|x| x})
    assert_equal [1, 2, Proc, :x], (pr.call(1, 2, 3){|x| x})
    assert_equal [1, 2, Proc, :x], (pr.call(1, 2, 3, 4){|x| x})
  end

  def test_proc_args_pos_rest_block
    pr = proc {|a,b,*c,&d|
      [a, b, c, d.class, d&&d.call(:x)]
    }
    assert_equal [nil, nil, [], NilClass, nil], pr.call()
    assert_equal [1, nil, [], NilClass, nil], pr.call(1)
    assert_equal [1, 2, [], NilClass, nil], pr.call(1,2)
    assert_equal [1, 2, [3], NilClass, nil], pr.call(1,2,3)
    assert_equal [1, 2, [3,4], NilClass, nil], pr.call(1,2,3,4)

    assert_equal [nil, nil, [], Proc, :proc], (pr.call(){ :proc })
    assert_equal [1, nil, [], Proc, :proc], (pr.call(1){ :proc })
    assert_equal [1, 2, [], Proc, :proc], (pr.call(1, 2){ :proc })
    assert_equal [1, 2, [3], Proc, :proc], (pr.call(1, 2, 3){ :proc })
    assert_equal [1, 2, [3,4], Proc, :proc], (pr.call(1, 2, 3, 4){ :proc })

    assert_equal [nil, nil, [], Proc, :x], (pr.call(){|x| x})
    assert_equal [1, nil, [], Proc, :x], (pr.call(1){|x| x})
    assert_equal [1, 2, [], Proc, :x], (pr.call(1, 2){|x| x})
    assert_equal [1, 2, [3], Proc, :x], (pr.call(1, 2, 3){|x| x})
    assert_equal [1, 2, [3,4], Proc, :x], (pr.call(1, 2, 3, 4){|x| x})
  end

  def test_proc_args_rest_block
    pr = proc {|*c,&d|
      [c, d.class, d&&d.call(:x)]
    }
    assert_equal [[], NilClass, nil], pr.call()
    assert_equal [[1], NilClass, nil], pr.call(1)
    assert_equal [[1, 2], NilClass, nil], pr.call(1,2)

    assert_equal [[], Proc, :proc], (pr.call(){ :proc })
    assert_equal [[1], Proc, :proc], (pr.call(1){ :proc })
    assert_equal [[1, 2], Proc, :proc], (pr.call(1, 2){ :proc })

    assert_equal [[], Proc, :x], (pr.call(){|x| x})
    assert_equal [[1], Proc, :x], (pr.call(1){|x| x})
    assert_equal [[1, 2], Proc, :x], (pr.call(1, 2){|x| x})
  end

  def test_proc_args_single_kw_no_autosplat
    pr = proc {|c, a: 1| [c, a] }
    assert_equal [nil, 1], pr.call()
    assert_equal [1, 1], pr.call(1)
    assert_equal [[1], 1], pr.call([1])
    assert_equal [1, 1], pr.call(1,2)
    assert_equal [[1, 2], 1], pr.call([1,2])

    assert_equal [nil, 3], pr.call(a: 3)
    assert_equal [1, 3], pr.call(1, a: 3)
    assert_equal [[1], 3], pr.call([1], a: 3)
    assert_equal [1, 3], pr.call(1,2, a: 3)
    assert_equal [[1, 2], 3], pr.call([1,2], a: 3)
  end

  def test_proc_args_single_kwsplat_no_autosplat
    pr = proc {|c, **kw| [c, kw] }
    assert_equal [nil, {}], pr.call()
    assert_equal [1, {}], pr.call(1)
    assert_equal [[1], {}], pr.call([1])
    assert_equal [1, {}], pr.call(1,2)
    assert_equal [[1, 2], {}], pr.call([1,2])

    assert_equal [nil, {a: 3}], pr.call(a: 3)
    assert_equal [1, {a: 3}], pr.call(1, a: 3)
    assert_equal [[1], {a: 3}], pr.call([1], a: 3)
    assert_equal [1, {a: 3}], pr.call(1,2, a: 3)
    assert_equal [[1, 2], {a: 3}], pr.call([1,2], a: 3)
  end

  def test_proc_args_multiple_kw_autosplat
    pr = proc {|c, b, a: 1| [c, b, a] }
    assert_equal [1, 2, 1], pr.call([1,2])

    pr = proc {|c=nil, b=nil, a: 1| [c, b, a] }
    assert_equal [nil, nil, 1], pr.call([])
    assert_equal [1, nil, 1], pr.call([1])
    assert_equal [1, 2, 1], pr.call([1,2])

    pr = proc {|c, b=nil, a: 1| [c, b, a] }
    assert_equal [1, nil, 1], pr.call([1])
    assert_equal [1, 2, 1], pr.call([1,2])

    pr = proc {|c=nil, b, a: 1| [c, b, a] }
    assert_equal [nil, 1, 1], pr.call([1])
    assert_equal [1, 2, 1], pr.call([1,2])

    pr = proc {|c, *b, a: 1| [c, b, a] }
    assert_equal [1, [], 1], pr.call([1])
    assert_equal [1, [2], 1], pr.call([1,2])

    pr = proc {|*c, b, a: 1| [c, b, a] }
    assert_equal [[], 1, 1], pr.call([1])
    assert_equal [[1], 2, 1], pr.call([1,2])
  end

  def test_proc_args_multiple_kwsplat_autosplat
    pr = proc {|c, b, **kw| [c, b, kw] }
    assert_equal [1, 2, {}], pr.call([1,2])

    pr = proc {|c=nil, b=nil, **kw| [c, b, kw] }
    assert_equal [nil, nil, {}], pr.call([])
    assert_equal [1, nil, {}], pr.call([1])
    assert_equal [1, 2, {}], pr.call([1,2])

    pr = proc {|c, b=nil, **kw| [c, b, kw] }
    assert_equal [1, nil, {}], pr.call([1])
    assert_equal [1, 2, {}], pr.call([1,2])

    pr = proc {|c=nil, b, **kw| [c, b, kw] }
    assert_equal [nil, 1, {}], pr.call([1])
    assert_equal [1, 2, {}], pr.call([1,2])

    pr = proc {|c, *b, **kw| [c, b, kw] }
    assert_equal [1, [], {}], pr.call([1])
    assert_equal [1, [2], {}], pr.call([1,2])

    pr = proc {|*c, b, **kw| [c, b, kw] }
    assert_equal [[], 1, {}], pr.call([1])
    assert_equal [[1], 2, {}], pr.call([1,2])
  end

  def test_proc_args_only_rest
    pr = proc {|*c| c }
    assert_equal [], pr.call()
    assert_equal [1], pr.call(1)
    assert_equal [[1]], pr.call([1])
    assert_equal [1, 2], pr.call(1,2)
    assert_equal [[1, 2]], pr.call([1,2])
  end

  def test_proc_args_rest_kw
    pr = proc {|*c, a: 1| [c, a] }
    assert_equal [[], 1], pr.call()
    assert_equal [[1], 1], pr.call(1)
    assert_equal [[[1]], 1], pr.call([1])
    assert_equal [[1, 2], 1], pr.call(1,2)
    assert_equal [[[1, 2]], 1], pr.call([1,2])
  end

  def test_proc_args_rest_kwsplat
    pr = proc {|*c, **kw| [c, kw] }
    assert_equal [[], {}], pr.call()
    assert_equal [[1], {}], pr.call(1)
    assert_equal [[[1]], {}], pr.call([1])
    assert_equal [[1, 2], {}], pr.call(1,2)
    assert_equal [[[1, 2]], {}], pr.call([1,2])
  end

  def test_proc_args_pos_rest_post_block
    pr = proc {|a,b,*c,d,e,&f|
      [a, b, c, d, e, f.class, f&&f.call(:x)]
    }
    assert_equal [nil, nil, [], nil, nil, NilClass, nil], pr.call()
    assert_equal [1, nil, [], nil, nil, NilClass, nil], pr.call(1)
    assert_equal [1, 2, [], nil, nil, NilClass, nil], pr.call(1,2)
    assert_equal [1, 2, [], 3, nil, NilClass, nil], pr.call(1,2,3)
    assert_equal [1, 2, [], 3, 4, NilClass, nil], pr.call(1,2,3,4)
    assert_equal [1, 2, [3], 4, 5, NilClass, nil], pr.call(1,2,3,4,5)
    assert_equal [1, 2, [3,4], 5, 6, NilClass, nil], pr.call(1,2,3,4,5,6)

    assert_equal [nil, nil, [], nil, nil, Proc, :proc], (pr.call(){ :proc })
    assert_equal [1, nil, [], nil, nil, Proc, :proc], (pr.call(1){ :proc })
    assert_equal [1, 2, [], nil, nil, Proc, :proc], (pr.call(1, 2){ :proc })
    assert_equal [1, 2, [], 3, nil, Proc, :proc], (pr.call(1, 2, 3){ :proc })
    assert_equal [1, 2, [], 3, 4, Proc, :proc], (pr.call(1, 2, 3, 4){ :proc })
    assert_equal [1, 2, [3], 4, 5, Proc, :proc], (pr.call(1, 2, 3, 4, 5){ :proc })
    assert_equal [1, 2, [3,4], 5, 6, Proc, :proc], (pr.call(1, 2, 3, 4, 5, 6){ :proc })

    assert_equal [nil, nil, [], nil, nil, Proc, :x], (pr.call(){|x| x})
    assert_equal [1, nil, [], nil, nil, Proc, :x], (pr.call(1){|x| x})
    assert_equal [1, 2, [], nil, nil, Proc, :x], (pr.call(1, 2){|x| x})
    assert_equal [1, 2, [], 3, nil, Proc, :x], (pr.call(1, 2, 3){|x| x})
    assert_equal [1, 2, [], 3, 4, Proc, :x], (pr.call(1, 2, 3, 4){|x| x})
    assert_equal [1, 2, [3], 4, 5, Proc, :x], (pr.call(1, 2, 3, 4, 5){|x| x})
    assert_equal [1, 2, [3,4], 5, 6, Proc, :x], (pr.call(1, 2, 3, 4, 5, 6){|x| x})
  end

  def test_proc_args_rest_post_block
    pr = proc {|*c,d,e,&f|
      [c, d, e, f.class, f&&f.call(:x)]
    }
    assert_equal [[], nil, nil, NilClass, nil], pr.call()
    assert_equal [[], 1, nil, NilClass, nil], pr.call(1)
    assert_equal [[], 1, 2, NilClass, nil], pr.call(1,2)
    assert_equal [[1], 2, 3, NilClass, nil], pr.call(1,2,3)
    assert_equal [[1, 2], 3, 4, NilClass, nil], pr.call(1,2,3,4)

    assert_equal [[], nil, nil, Proc, :proc], (pr.call(){ :proc })
    assert_equal [[], 1, nil, Proc, :proc], (pr.call(1){ :proc })
    assert_equal [[], 1, 2, Proc, :proc], (pr.call(1, 2){ :proc })
    assert_equal [[1], 2, 3, Proc, :proc], (pr.call(1, 2, 3){ :proc })
    assert_equal [[1, 2], 3, 4, Proc, :proc], (pr.call(1, 2, 3, 4){ :proc })

    assert_equal [[], nil, nil, Proc, :x], (pr.call(){|x| x})
    assert_equal [[], 1, nil, Proc, :x], (pr.call(1){|x| x})
    assert_equal [[], 1, 2, Proc, :x], (pr.call(1, 2){|x| x})
    assert_equal [[1], 2, 3, Proc, :x], (pr.call(1, 2, 3){|x| x})
    assert_equal [[1, 2], 3, 4, Proc, :x], (pr.call(1, 2, 3, 4){|x| x})
  end

  def test_proc_args_pos_opt_block
    pr = proc {|a,b,c=:c,d=:d,&e|
      [a, b, c, d, e.class, e&&e.call(:x)]
    }
    assert_equal [nil, nil, :c, :d, NilClass, nil], pr.call()
    assert_equal [1, nil, :c, :d, NilClass, nil], pr.call(1)
    assert_equal [1, 2, :c, :d, NilClass, nil], pr.call(1,2)
    assert_equal [1, 2, 3, :d, NilClass, nil], pr.call(1,2,3)
    assert_equal [1, 2, 3, 4, NilClass, nil], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, 4, NilClass, nil], pr.call(1,2,3,4,5)

    assert_equal [nil, nil, :c, :d, Proc, :proc], (pr.call(){ :proc })
    assert_equal [1, nil, :c, :d, Proc, :proc], (pr.call(1){ :proc })
    assert_equal [1, 2, :c, :d, Proc, :proc], (pr.call(1, 2){ :proc })
    assert_equal [1, 2, 3, :d, Proc, :proc], (pr.call(1, 2, 3){ :proc })
    assert_equal [1, 2, 3, 4, Proc, :proc], (pr.call(1, 2, 3, 4){ :proc })
    assert_equal [1, 2, 3, 4, Proc, :proc], (pr.call(1, 2, 3, 4, 5){ :proc })

    assert_equal [nil, nil, :c, :d, Proc, :x], (pr.call(){|x| x})
    assert_equal [1, nil, :c, :d, Proc, :x], (pr.call(1){|x| x})
    assert_equal [1, 2, :c, :d, Proc, :x], (pr.call(1, 2){|x| x})
    assert_equal [1, 2, 3, :d, Proc, :x], (pr.call(1, 2, 3){|x| x})
    assert_equal [1, 2, 3, 4, Proc, :x], (pr.call(1, 2, 3, 4){|x| x})
    assert_equal [1, 2, 3, 4, Proc, :x], (pr.call(1, 2, 3, 4, 5){|x| x})
  end

  def test_proc_args_opt_block
    pr = proc {|a=:a,b=:b,c=:c,d=:d,&e|
      [a, b, c, d, e.class, e&&e.call(:x)]
    }
    assert_equal [:a, :b, :c, :d, NilClass, nil], pr.call()
    assert_equal [1, :b, :c, :d, NilClass, nil], pr.call(1)
    assert_equal [1, 2, :c, :d, NilClass, nil], pr.call(1,2)
    assert_equal [1, 2, 3, :d, NilClass, nil], pr.call(1,2,3)
    assert_equal [1, 2, 3, 4, NilClass, nil], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, 4, NilClass, nil], pr.call(1,2,3,4,5)

    assert_equal [:a, :b, :c, :d, Proc, :proc], (pr.call(){ :proc })
    assert_equal [1, :b, :c, :d, Proc, :proc], (pr.call(1){ :proc })
    assert_equal [1, 2, :c, :d, Proc, :proc], (pr.call(1, 2){ :proc })
    assert_equal [1, 2, 3, :d, Proc, :proc], (pr.call(1, 2, 3){ :proc })
    assert_equal [1, 2, 3, 4, Proc, :proc], (pr.call(1, 2, 3, 4){ :proc })
    assert_equal [1, 2, 3, 4, Proc, :proc], (pr.call(1, 2, 3, 4, 5){ :proc })

    assert_equal [:a, :b, :c, :d, Proc, :x], (pr.call(){|x| x})
    assert_equal [1, :b, :c, :d, Proc, :x], (pr.call(1){|x| x})
    assert_equal [1, 2, :c, :d, Proc, :x], (pr.call(1, 2){|x| x})
    assert_equal [1, 2, 3, :d, Proc, :x], (pr.call(1, 2, 3){|x| x})
    assert_equal [1, 2, 3, 4, Proc, :x], (pr.call(1, 2, 3, 4){|x| x})
    assert_equal [1, 2, 3, 4, Proc, :x], (pr.call(1, 2, 3, 4, 5){|x| x})
  end

  def test_proc_args_pos_opt_post_block
    pr = proc {|a,b,c=:c,d=:d,e,f,&g|
      [a, b, c, d, e, f, g.class, g&&g.call(:x)]
    }
    assert_equal [nil, nil, :c, :d, nil, nil, NilClass, nil], pr.call()
    assert_equal [1, nil, :c, :d, nil, nil, NilClass, nil], pr.call(1)
    assert_equal [1, 2, :c, :d, nil, nil, NilClass, nil], pr.call(1,2)
    assert_equal [1, 2, :c, :d, 3, nil, NilClass, nil], pr.call(1,2,3)
    assert_equal [1, 2, :c, :d, 3, 4, NilClass, nil], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, :d, 4, 5, NilClass, nil], pr.call(1,2,3,4,5)
    assert_equal [1, 2, 3, 4, 5, 6, NilClass, nil], pr.call(1,2,3,4,5,6)
    assert_equal [1, 2, 3, 4, 5, 6, NilClass, nil], pr.call(1,2,3,4,5,6,7)

    assert_equal [nil, nil, :c, :d, nil, nil, Proc, :proc], (pr.call(){ :proc })
    assert_equal [1, nil, :c, :d, nil, nil, Proc, :proc], (pr.call(1){ :proc })
    assert_equal [1, 2, :c, :d, nil, nil, Proc, :proc], (pr.call(1, 2){ :proc })
    assert_equal [1, 2, :c, :d, 3, nil, Proc, :proc], (pr.call(1, 2, 3){ :proc })
    assert_equal [1, 2, :c, :d, 3, 4, Proc, :proc], (pr.call(1, 2, 3, 4){ :proc })
    assert_equal [1, 2, 3, :d, 4, 5, Proc, :proc], (pr.call(1, 2, 3, 4, 5){ :proc })
    assert_equal [1, 2, 3, 4, 5, 6, Proc, :proc], (pr.call(1, 2, 3, 4, 5, 6){ :proc })
    assert_equal [1, 2, 3, 4, 5, 6, Proc, :proc], (pr.call(1, 2, 3, 4, 5, 6, 7){ :proc })

    assert_equal [nil, nil, :c, :d, nil, nil, Proc, :x], (pr.call(){|x| x})
    assert_equal [1, nil, :c, :d, nil, nil, Proc, :x], (pr.call(1){|x| x})
    assert_equal [1, 2, :c, :d, nil, nil, Proc, :x], (pr.call(1, 2){|x| x})
    assert_equal [1, 2, :c, :d, 3, nil, Proc, :x], (pr.call(1, 2, 3){|x| x})
    assert_equal [1, 2, :c, :d, 3, 4, Proc, :x], (pr.call(1, 2, 3, 4){|x| x})
    assert_equal [1, 2, 3, :d, 4, 5, Proc, :x], (pr.call(1, 2, 3, 4, 5){|x| x})
    assert_equal [1, 2, 3, 4, 5, 6, Proc, :x], (pr.call(1, 2, 3, 4, 5, 6){|x| x})
    assert_equal [1, 2, 3, 4, 5, 6, Proc, :x], (pr.call(1, 2, 3, 4, 5, 6, 7){|x| x})
  end

  def test_proc_args_opt_post_block
    pr = proc {|a=:a,b=:b,c=:c,d=:d,e,f,&g|
      [a, b, c, d, e, f, g.class, g&&g.call(:x)]
    }
    assert_equal [:a, :b, :c, :d, nil, nil, NilClass, nil], pr.call()
    assert_equal [:a, :b, :c, :d, 1, nil, NilClass, nil], pr.call(1)
    assert_equal [:a, :b, :c, :d, 1, 2, NilClass, nil], pr.call(1,2)
    assert_equal [1, :b, :c, :d, 2, 3, NilClass, nil], pr.call(1,2,3)
    assert_equal [1, 2, :c, :d, 3, 4, NilClass, nil], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, :d, 4, 5, NilClass, nil], pr.call(1,2,3,4,5)
    assert_equal [1, 2, 3, 4, 5, 6, NilClass, nil], pr.call(1,2,3,4,5,6)
    assert_equal [1, 2, 3, 4, 5, 6, NilClass, nil], pr.call(1,2,3,4,5,6,7)

    assert_equal [:a, :b, :c, :d, nil, nil, Proc, :proc], (pr.call(){ :proc })
    assert_equal [:a, :b, :c, :d, 1, nil, Proc, :proc], (pr.call(1){ :proc })
    assert_equal [:a, :b, :c, :d, 1, 2, Proc, :proc], (pr.call(1, 2){ :proc })
    assert_equal [1, :b, :c, :d, 2, 3, Proc, :proc], (pr.call(1, 2, 3){ :proc })
    assert_equal [1, 2, :c, :d, 3, 4, Proc, :proc], (pr.call(1, 2, 3, 4){ :proc })
    assert_equal [1, 2, 3, :d, 4, 5, Proc, :proc], (pr.call(1, 2, 3, 4, 5){ :proc })
    assert_equal [1, 2, 3, 4, 5, 6, Proc, :proc], (pr.call(1, 2, 3, 4, 5, 6){ :proc })
    assert_equal [1, 2, 3, 4, 5, 6, Proc, :proc], (pr.call(1, 2, 3, 4, 5, 6, 7){ :proc })

    assert_equal [:a, :b, :c, :d, nil, nil, Proc, :x], (pr.call(){|x| x})
    assert_equal [:a, :b, :c, :d, 1, nil, Proc, :x], (pr.call(1){|x| x})
    assert_equal [:a, :b, :c, :d, 1, 2, Proc, :x], (pr.call(1, 2){|x| x})
    assert_equal [1, :b, :c, :d, 2, 3, Proc, :x], (pr.call(1, 2, 3){|x| x})
    assert_equal [1, 2, :c, :d, 3, 4, Proc, :x], (pr.call(1, 2, 3, 4){|x| x})
    assert_equal [1, 2, 3, :d, 4, 5, Proc, :x], (pr.call(1, 2, 3, 4, 5){|x| x})
    assert_equal [1, 2, 3, 4, 5, 6, Proc, :x], (pr.call(1, 2, 3, 4, 5, 6){|x| x})
    assert_equal [1, 2, 3, 4, 5, 6, Proc, :x], (pr.call(1, 2, 3, 4, 5, 6, 7){|x| x})
  end

  def test_proc_args_pos_opt_rest_block
    pr = proc {|a,b,c=:c,d=:d,*e,&f|
      [a, b, c, d, e, f.class, f&&f.call(:x)]
    }
    assert_equal [nil, nil, :c, :d, [], NilClass, nil], pr.call()
    assert_equal [1, nil, :c, :d, [], NilClass, nil], pr.call(1)
    assert_equal [1, 2, :c, :d, [], NilClass, nil], pr.call(1,2)
    assert_equal [1, 2, 3, :d, [], NilClass, nil], pr.call(1,2,3)
    assert_equal [1, 2, 3, 4, [], NilClass, nil], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, 4, [5], NilClass, nil], pr.call(1,2,3,4,5)
    assert_equal [1, 2, 3, 4, [5,6], NilClass, nil], pr.call(1,2,3,4,5,6)

    assert_equal [nil, nil, :c, :d, [], Proc, :proc], (pr.call(){ :proc })
    assert_equal [1, nil, :c, :d, [], Proc, :proc], (pr.call(1){ :proc })
    assert_equal [1, 2, :c, :d, [], Proc, :proc], (pr.call(1, 2){ :proc })
    assert_equal [1, 2, 3, :d, [], Proc, :proc], (pr.call(1, 2, 3){ :proc })
    assert_equal [1, 2, 3, 4, [], Proc, :proc], (pr.call(1, 2, 3, 4){ :proc })
    assert_equal [1, 2, 3, 4, [5], Proc, :proc], (pr.call(1, 2, 3, 4, 5){ :proc })
    assert_equal [1, 2, 3, 4, [5,6], Proc, :proc], (pr.call(1, 2, 3, 4, 5, 6){ :proc })

    assert_equal [nil, nil, :c, :d, [], Proc, :x], (pr.call(){|x| x})
    assert_equal [1, nil, :c, :d, [], Proc, :x], (pr.call(1){|x| x})
    assert_equal [1, 2, :c, :d, [], Proc, :x], (pr.call(1, 2){|x| x})
    assert_equal [1, 2, 3, :d, [], Proc, :x], (pr.call(1, 2, 3){|x| x})
    assert_equal [1, 2, 3, 4, [], Proc, :x], (pr.call(1, 2, 3, 4){|x| x})
    assert_equal [1, 2, 3, 4, [5], Proc, :x], (pr.call(1, 2, 3, 4, 5){|x| x})
    assert_equal [1, 2, 3, 4, [5,6], Proc, :x], (pr.call(1, 2, 3, 4, 5, 6){|x| x})
  end

  def test_proc_args_opt_rest_block
    pr = proc {|a=:a,b=:b,c=:c,d=:d,*e,&f|
      [a, b, c, d, e, f.class, f&&f.call(:x)]
    }
    assert_equal [:a, :b, :c, :d, [], NilClass, nil], pr.call()
    assert_equal [1, :b, :c, :d, [], NilClass, nil], pr.call(1)
    assert_equal [1, 2, :c, :d, [], NilClass, nil], pr.call(1,2)
    assert_equal [1, 2, 3, :d, [], NilClass, nil], pr.call(1,2,3)
    assert_equal [1, 2, 3, 4, [], NilClass, nil], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, 4, [5], NilClass, nil], pr.call(1,2,3,4,5)
    assert_equal [1, 2, 3, 4, [5,6], NilClass, nil], pr.call(1,2,3,4,5,6)

    assert_equal [:a, :b, :c, :d, [], Proc, :proc], (pr.call(){ :proc })
    assert_equal [1, :b, :c, :d, [], Proc, :proc], (pr.call(1){ :proc })
    assert_equal [1, 2, :c, :d, [], Proc, :proc], (pr.call(1, 2){ :proc })
    assert_equal [1, 2, 3, :d, [], Proc, :proc], (pr.call(1, 2, 3){ :proc })
    assert_equal [1, 2, 3, 4, [], Proc, :proc], (pr.call(1, 2, 3, 4){ :proc })
    assert_equal [1, 2, 3, 4, [5], Proc, :proc], (pr.call(1, 2, 3, 4, 5){ :proc })
    assert_equal [1, 2, 3, 4, [5,6], Proc, :proc], (pr.call(1, 2, 3, 4, 5, 6){ :proc })

    assert_equal [:a, :b, :c, :d, [], Proc, :x], (pr.call(){|x| x})
    assert_equal [1, :b, :c, :d, [], Proc, :x], (pr.call(1){|x| x})
    assert_equal [1, 2, :c, :d, [], Proc, :x], (pr.call(1, 2){|x| x})
    assert_equal [1, 2, 3, :d, [], Proc, :x], (pr.call(1, 2, 3){|x| x})
    assert_equal [1, 2, 3, 4, [], Proc, :x], (pr.call(1, 2, 3, 4){|x| x})
    assert_equal [1, 2, 3, 4, [5], Proc, :x], (pr.call(1, 2, 3, 4, 5){|x| x})
    assert_equal [1, 2, 3, 4, [5,6], Proc, :x], (pr.call(1, 2, 3, 4, 5, 6){|x| x})
  end

  def test_proc_args_pos_opt_rest_post_block
    pr = proc {|a,b,c=:c,d=:d,*e,f,g,&h|
      [a, b, c, d, e, f, g, h.class, h&&h.call(:x)]
    }
    assert_equal [nil, nil, :c, :d, [], nil, nil, NilClass, nil], pr.call()
    assert_equal [1, nil, :c, :d, [], nil, nil, NilClass, nil], pr.call(1)
    assert_equal [1, 2, :c, :d, [], nil, nil, NilClass, nil], pr.call(1,2)
    assert_equal [1, 2, :c, :d, [], 3, nil, NilClass, nil], pr.call(1,2,3)
    assert_equal [1, 2, :c, :d, [], 3, 4, NilClass, nil], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, :d, [], 4, 5, NilClass, nil], pr.call(1,2,3,4,5)
    assert_equal [1, 2, 3, 4, [], 5, 6, NilClass, nil], pr.call(1,2,3,4,5,6)
    assert_equal [1, 2, 3, 4, [5], 6, 7, NilClass, nil], pr.call(1,2,3,4,5,6,7)
    assert_equal [1, 2, 3, 4, [5,6], 7, 8, NilClass, nil], pr.call(1,2,3,4,5,6,7,8)

    assert_equal [nil, nil, :c, :d, [], nil, nil, Proc, :proc], (pr.call(){ :proc })
    assert_equal [1, nil, :c, :d, [], nil, nil, Proc, :proc], (pr.call(1){ :proc })
    assert_equal [1, 2, :c, :d, [], nil, nil, Proc, :proc], (pr.call(1, 2){ :proc })
    assert_equal [1, 2, :c, :d, [], 3, nil, Proc, :proc], (pr.call(1, 2, 3){ :proc })
    assert_equal [1, 2, :c, :d, [], 3, 4, Proc, :proc], (pr.call(1, 2, 3, 4){ :proc })
    assert_equal [1, 2, 3, :d, [], 4, 5, Proc, :proc], (pr.call(1, 2, 3, 4, 5){ :proc })
    assert_equal [1, 2, 3, 4, [], 5, 6, Proc, :proc], (pr.call(1, 2, 3, 4, 5, 6){ :proc })
    assert_equal [1, 2, 3, 4, [5], 6, 7, Proc, :proc], (pr.call(1, 2, 3, 4, 5, 6, 7){ :proc })
    assert_equal [1, 2, 3, 4, [5,6], 7, 8, Proc, :proc], (pr.call(1, 2, 3, 4, 5, 6, 7, 8){ :proc })

    assert_equal [nil, nil, :c, :d, [], nil, nil, Proc, :x], (pr.call(){|x| x})
    assert_equal [1, nil, :c, :d, [], nil, nil, Proc, :x], (pr.call(1){|x| x})
    assert_equal [1, 2, :c, :d, [], nil, nil, Proc, :x], (pr.call(1, 2){|x| x})
    assert_equal [1, 2, :c, :d, [], 3, nil, Proc, :x], (pr.call(1, 2, 3){|x| x})
    assert_equal [1, 2, :c, :d, [], 3, 4, Proc, :x], (pr.call(1, 2, 3, 4){|x| x})
    assert_equal [1, 2, 3, :d, [], 4, 5, Proc, :x], (pr.call(1, 2, 3, 4, 5){|x| x})
    assert_equal [1, 2, 3, 4, [], 5, 6, Proc, :x], (pr.call(1, 2, 3, 4, 5, 6){|x| x})
    assert_equal [1, 2, 3, 4, [5], 6, 7, Proc, :x], (pr.call(1, 2, 3, 4, 5, 6, 7){|x| x})
    assert_equal [1, 2, 3, 4, [5,6], 7, 8, Proc, :x], (pr.call(1, 2, 3, 4, 5, 6, 7, 8){|x| x})
  end

  def test_proc_args_opt_rest_post_block
    pr = proc {|a=:a,b=:b,c=:c,d=:d,*e,f,g,&h|
      [a, b, c, d, e, f, g, h.class, h&&h.call(:x)]
    }
    assert_equal [:a, :b, :c, :d, [], nil, nil, NilClass, nil], pr.call()
    assert_equal [:a, :b, :c, :d, [], 1, nil, NilClass, nil], pr.call(1)
    assert_equal [:a, :b, :c, :d, [], 1, 2, NilClass, nil], pr.call(1,2)
    assert_equal [1, :b, :c, :d, [], 2, 3, NilClass, nil], pr.call(1,2,3)
    assert_equal [1, 2, :c, :d, [], 3, 4, NilClass, nil], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, :d, [], 4, 5, NilClass, nil], pr.call(1,2,3,4,5)
    assert_equal [1, 2, 3, 4, [], 5, 6, NilClass, nil], pr.call(1,2,3,4,5,6)
    assert_equal [1, 2, 3, 4, [5], 6, 7, NilClass, nil], pr.call(1,2,3,4,5,6,7)
    assert_equal [1, 2, 3, 4, [5,6], 7, 8, NilClass, nil], pr.call(1,2,3,4,5,6,7,8)

    assert_equal [:a, :b, :c, :d, [], nil, nil, Proc, :proc], (pr.call(){ :proc })
    assert_equal [:a, :b, :c, :d, [], 1, nil, Proc, :proc], (pr.call(1){ :proc })
    assert_equal [:a, :b, :c, :d, [], 1, 2, Proc, :proc], (pr.call(1, 2){ :proc })
    assert_equal [1, :b, :c, :d, [], 2, 3, Proc, :proc], (pr.call(1, 2, 3){ :proc })
    assert_equal [1, 2, :c, :d, [], 3, 4, Proc, :proc], (pr.call(1, 2, 3, 4){ :proc })
    assert_equal [1, 2, 3, :d, [], 4, 5, Proc, :proc], (pr.call(1, 2, 3, 4, 5){ :proc })
    assert_equal [1, 2, 3, 4, [], 5, 6, Proc, :proc], (pr.call(1, 2, 3, 4, 5, 6){ :proc })
    assert_equal [1, 2, 3, 4, [5], 6, 7, Proc, :proc], (pr.call(1, 2, 3, 4, 5, 6, 7){ :proc })
    assert_equal [1, 2, 3, 4, [5,6], 7, 8, Proc, :proc], (pr.call(1, 2, 3, 4, 5, 6, 7, 8){ :proc })

    assert_equal [:a, :b, :c, :d, [], nil, nil, Proc, :x], (pr.call(){|x| x})
    assert_equal [:a, :b, :c, :d, [], 1, nil, Proc, :x], (pr.call(1){|x| x})
    assert_equal [:a, :b, :c, :d, [], 1, 2, Proc, :x], (pr.call(1, 2){|x| x})
    assert_equal [1, :b, :c, :d, [], 2, 3, Proc, :x], (pr.call(1, 2, 3){|x| x})
    assert_equal [1, 2, :c, :d, [], 3, 4, Proc, :x], (pr.call(1, 2, 3, 4){|x| x})
    assert_equal [1, 2, 3, :d, [], 4, 5, Proc, :x], (pr.call(1, 2, 3, 4, 5){|x| x})
    assert_equal [1, 2, 3, 4, [], 5, 6, Proc, :x], (pr.call(1, 2, 3, 4, 5, 6){|x| x})
    assert_equal [1, 2, 3, 4, [5], 6, 7, Proc, :x], (pr.call(1, 2, 3, 4, 5, 6, 7){|x| x})
    assert_equal [1, 2, 3, 4, [5,6], 7, 8, Proc, :x], (pr.call(1, 2, 3, 4, 5, 6, 7, 8){|x| x})
  end

  def test_proc_args_pos_unleashed
    r = proc {|a,b=1,*c,d,e|
      [a,b,c,d,e]
    }.call(1,2,3,4,5)
    assert_equal([1,2,[3],4,5], r, "[ruby-core:19485]")
  end

  def test_proc_autosplat
    def self.a(arg, kw)
      yield arg
      yield arg, **kw
      yield arg, kw
    end

    arr = []
    a([1,2,3], {}) do |arg1, arg2=0|
      arr << [arg1, arg2]
    end
    assert_equal([[1, 2], [[1, 2, 3], 0], [[1, 2, 3], {}]], arr)

    arr = []
    a([1,2,3], a: 1) do |arg1, arg2=0|
      arr << [arg1, arg2]
    end
    assert_equal([[1, 2], [[1, 2, 3], {a: 1}], [[1, 2, 3], {a: 1}]], arr)
  end

  def test_proc_single_arg_with_keywords_accepted_and_yielded
    def self.a
      yield [], **{a: 1}
    end
    res = a do |arg, **opts|
      [arg, opts]
    end
    assert_equal([[], {a: 1}], res)
  end

  def test_parameters
    assert_equal([], proc {}.parameters)
    assert_equal([], proc {||}.parameters)
    assert_equal([[:opt, :a]], proc {|a|}.parameters)
    assert_equal([[:opt, :a], [:opt, :b]], proc {|a, b|}.parameters)
    assert_equal([[:opt, :a], [:block, :b]], proc {|a=:a, &b|}.parameters)
    assert_equal([[:opt, :a], [:opt, :b]], proc {|a, b=:b|}.parameters)
    assert_equal([[:rest, :a]], proc {|*a|}.parameters)
    assert_equal([[:opt, :a], [:rest, :b], [:block, :c]], proc {|a, *b, &c|}.parameters)
    assert_equal([[:opt, :a], [:rest, :b], [:opt, :c]], proc {|a, *b, c|}.parameters)
    assert_equal([[:opt, :a], [:rest, :b], [:opt, :c], [:block, :d]], proc {|a, *b, c, &d|}.parameters)
    assert_equal([[:opt, :a], [:opt, :b], [:rest, :c], [:opt, :d], [:block, :e]], proc {|a, b=:b, *c, d, &e|}.parameters)
    assert_equal([[:opt], [:block, :b]], proc {|(a), &b|a}.parameters)
    assert_equal([[:opt], [:rest, :_], [:opt]], proc {|(a_), *_, (b_)|}.parameters)
    assert_equal([[:opt, :a], [:opt, :b], [:opt, :c], [:opt, :d], [:rest, :e], [:opt, :f], [:opt, :g], [:block, :h]], proc {|a,b,c=:c,d=:d,*e,f,g,&h|}.parameters)

    assert_equal([[:req]], method(:putc).parameters)
    assert_equal([[:rest]], method(:p).parameters)

    pr = eval("proc{|"+"(_),"*30+"|}")
    assert_empty(pr.parameters.map{|_,n|n}.compact)

    assert_equal([[:opt]], proc { it }.parameters)
  end

  def test_proc_autosplat_with_multiple_args_with_ruby2_keywords_splat_bug_19759
    def self.yielder_ab(splat)
      yield([:a, :b], *splat)
    end

    res = yielder_ab([[:aa, :bb], Hash.ruby2_keywords_hash({k: :k})]) do |a, b, k:|
      [a, b, k]
    end
    assert_equal([[:a, :b], [:aa, :bb], :k], res)

    def self.yielder(splat)
      yield(*splat)
    end
    res = yielder([ [:a, :b] ]){|a, b, **| [a, b]}
    assert_equal([:a, :b], res)

    res = yielder([ [:a, :b], Hash.ruby2_keywords_hash({}) ]){|a, b, **| [a, b]}
    assert_equal([[:a, :b], nil], res)

    res = yielder([ [:a, :b], Hash.ruby2_keywords_hash({c: 1}) ]){|a, b, **| [a, b]}
    assert_equal([[:a, :b], nil], res)

    res = yielder([ [:a, :b], Hash.ruby2_keywords_hash({}) ]){|a, b, **nil| [a, b]}
    assert_equal([[:a, :b], nil], res)
  end

  def test_parameters_lambda
    assert_equal([], proc {}.parameters(lambda: true))
    assert_equal([], proc {||}.parameters(lambda: true))
    assert_equal([[:req, :a]], proc {|a|}.parameters(lambda: true))
    assert_equal([[:req, :a], [:req, :b]], proc {|a, b|}.parameters(lambda: true))
    assert_equal([[:opt, :a], [:block, :b]], proc {|a=:a, &b|}.parameters(lambda: true))
    assert_equal([[:req, :a], [:opt, :b]], proc {|a, b=:b|}.parameters(lambda: true))
    assert_equal([[:rest, :a]], proc {|*a|}.parameters(lambda: true))
    assert_equal([[:req, :a], [:rest, :b], [:block, :c]], proc {|a, *b, &c|}.parameters(lambda: true))
    assert_equal([[:req, :a], [:rest, :b], [:req, :c]], proc {|a, *b, c|}.parameters(lambda: true))
    assert_equal([[:req, :a], [:rest, :b], [:req, :c], [:block, :d]], proc {|a, *b, c, &d|}.parameters(lambda: true))
    assert_equal([[:req, :a], [:opt, :b], [:rest, :c], [:req, :d], [:block, :e]], proc {|a, b=:b, *c, d, &e|}.parameters(lambda: true))
    assert_equal([[:req], [:block, :b]], proc {|(a), &b|a}.parameters(lambda: true))
    assert_equal([[:req, :a], [:req, :b], [:opt, :c], [:opt, :d], [:rest, :e], [:req, :f], [:req, :g], [:block, :h]], proc {|a,b,c=:c,d=:d,*e,f,g,&h|}.parameters(lambda: true))

    pr = eval("proc{|"+"(_),"*30+"|}")
    assert_empty(pr.parameters(lambda: true).map{|_,n|n}.compact)

    assert_equal([[:opt, :a]], lambda {|a|}.parameters(lambda: false))
    assert_equal([[:opt, :a], [:opt, :b], [:opt, :c], [:opt, :d], [:rest, :e], [:opt, :f], [:opt, :g], [:block, :h]], lambda {|a,b,c=:c,d=:d,*e,f,g,&h|}.parameters(lambda: false))

    assert_equal([[:req]], proc { it }.parameters(lambda: true))
    assert_equal([[:opt]], lambda { it }.parameters(lambda: false))
  end

  def pm0() end
  def pm1(a) end
  def pm2(a, b) end
  def pmo1(a = :a, &b) end
  def pmo2(a, b = :b) end
  def pmo3(*a) end
  def pmo4(a, *b, &c) end
  def pmo5(a, *b, c) end
  def pmo6(a, *b, c, &d) end
  def pmo7(a, b = :b, *c, d, &e) end
  def pma1((a), &b) a; end
  def pmk1(**) end
  def pmk2(**o) nil && o end
  def pmk3(a, **o) nil && o end
  def pmk4(a = nil, **o) nil && o end
  def pmk5(a, b = nil, **o) nil && o end
  def pmk6(a, b = nil, c, **o) nil && o end
  def pmk7(a, b = nil, *c, d, **o) nil && o end


  def test_bound_parameters
    assert_equal([], method(:pm0).to_proc.parameters)
    assert_equal([[:req, :a]], method(:pm1).to_proc.parameters)
    assert_equal([[:req, :a], [:req, :b]], method(:pm2).to_proc.parameters)
    assert_equal([[:opt, :a], [:block, :b]], method(:pmo1).to_proc.parameters)
    assert_equal([[:req, :a], [:opt, :b]], method(:pmo2).to_proc.parameters)
    assert_equal([[:rest, :a]], method(:pmo3).to_proc.parameters)
    assert_equal([[:req, :a], [:rest, :b], [:block, :c]], method(:pmo4).to_proc.parameters)
    assert_equal([[:req, :a], [:rest, :b], [:req, :c]], method(:pmo5).to_proc.parameters)
    assert_equal([[:req, :a], [:rest, :b], [:req, :c], [:block, :d]], method(:pmo6).to_proc.parameters)
    assert_equal([[:req, :a], [:opt, :b], [:rest, :c], [:req, :d], [:block, :e]], method(:pmo7).to_proc.parameters)
    assert_equal([[:req], [:block, :b]], method(:pma1).to_proc.parameters)
    assert_equal([[:keyrest, :**]], method(:pmk1).to_proc.parameters)
    assert_equal([[:keyrest, :o]], method(:pmk2).to_proc.parameters)
    assert_equal([[:req, :a], [:keyrest, :o]], method(:pmk3).to_proc.parameters)
    assert_equal([[:opt, :a], [:keyrest, :o]], method(:pmk4).to_proc.parameters)
    assert_equal([[:req, :a], [:opt, :b], [:keyrest, :o]], method(:pmk5).to_proc.parameters)
    assert_equal([[:req, :a], [:opt, :b], [:req, :c], [:keyrest, :o]], method(:pmk6).to_proc.parameters)
    assert_equal([[:req, :a], [:opt, :b], [:rest, :c], [:req, :d], [:keyrest, :o]], method(:pmk7).to_proc.parameters)

    assert_equal([], "".method(:empty?).to_proc.parameters)
    assert_equal([[:rest]], "".method(:gsub).to_proc.parameters)
    assert_equal([[:rest]], proc {}.curry.parameters)
  end

  def test_to_s
    assert_match(/^#<Proc:0x\h+ #{ Regexp.quote(__FILE__) }:\d+>$/, proc {}.to_s)
    assert_match(/^#<Proc:0x\h+ #{ Regexp.quote(__FILE__) }:\d+ \(lambda\)>$/, lambda {}.to_s)
    assert_match(/^#<Proc:0x\h+ \(lambda\)>$/, method(:p).to_proc.to_s)
    name = "Proc\u{1f37b}"
    assert_include(EnvUtil.labeled_class(name, Proc).new {}.to_s, name)
  end

  @@line_of_source_location_test = __LINE__ + 1
  def source_location_test a=1,
    b=2
  end

  def test_source_location
    file, lineno = method(:source_location_test).source_location
    assert_match(/^#{ Regexp.quote(__FILE__) }$/, file)
    assert_equal(@@line_of_source_location_test, lineno, 'Bug #2427')
  end

  @@line_of_attr_reader_source_location_test   = __LINE__ + 3
  @@line_of_attr_writer_source_location_test   = __LINE__ + 3
  @@line_of_attr_accessor_source_location_test = __LINE__ + 3
  attr_reader   :attr_reader_source_location_test
  attr_writer   :attr_writer_source_location_test
  attr_accessor :attr_accessor_source_location_test

  def test_attr_source_location
    file, lineno = method(:attr_reader_source_location_test).source_location
    assert_match(/^#{ Regexp.quote(__FILE__) }$/, file)
    assert_equal(@@line_of_attr_reader_source_location_test, lineno)

    file, lineno = method(:attr_writer_source_location_test=).source_location
    assert_match(/^#{ Regexp.quote(__FILE__) }$/, file)
    assert_equal(@@line_of_attr_writer_source_location_test, lineno)

    file, lineno = method(:attr_accessor_source_location_test).source_location
    assert_match(/^#{ Regexp.quote(__FILE__) }$/, file)
    assert_equal(@@line_of_attr_accessor_source_location_test, lineno)

    file, lineno = method(:attr_accessor_source_location_test=).source_location
    assert_match(/^#{ Regexp.quote(__FILE__) }$/, file)
    assert_equal(@@line_of_attr_accessor_source_location_test, lineno)
  end

  def block_source_location_test(*args, &block)
    block.source_location
  end

  def test_block_source_location
    exp_lineno = __LINE__ + 3
    file, lineno = block_source_location_test(1,
                                              2,
                                              3) do
                                              end
    assert_match(/^#{ Regexp.quote(__FILE__) }$/, file)
    assert_equal(exp_lineno, lineno)
  end

  def test_splat_without_respond_to
    def (obj = Object.new).respond_to?(m,*); false end
    [obj].each do |a, b|
      assert_equal([obj, nil], [a, b], '[ruby-core:24139]')
    end
  end

  def test_curry_with_trace
    # bug3751 = '[ruby-core:31871]'
    set_trace_func(proc {})
    methods.grep(/\Atest_curry/) do |test|
      next if test == __method__
      __send__(test)
    end
  ensure
    set_trace_func(nil)
  end

  def test_block_propagation
    bug3792 = '[ruby-core:32075]'
    c = Class.new do
      def foo
        yield
      end
    end

    o = c.new
    f = :foo.to_proc
    assert_nothing_raised(LocalJumpError, bug3792) {
      assert_equal('bar', f.(o) {'bar'}, bug3792)
    }
    assert_nothing_raised(LocalJumpError, bug3792) {
      assert_equal('zot', o.method(:foo).to_proc.() {'zot'}, bug3792)
    }
  end

  def test_overridden_lambda
    bug8345 = '[ruby-core:54687] [Bug #8345]'
    assert_normal_exit('def lambda; end; method(:puts).to_proc', bug8345)
  end

  def test_overridden_proc
    bug8345 = '[ruby-core:54688] [Bug #8345]'
    assert_normal_exit('def proc; end; ->{}.curry', bug8345)
  end

  def get_binding if: 1, case: 2, when: 3, begin: 4, end: 5
    a ||= 0
    binding
  end

  def test_local_variables
    b = get_binding
    assert_equal(%i'if case when begin end a', b.local_variables)
    a = tap {|;x, y| x = y = x; break binding.local_variables}
    assert_equal(%i[a b x y], a.sort)
  end

  def test_local_variables_nested
    b = tap {break binding}
    assert_equal(%i[b], b.local_variables, '[ruby-dev:48351] [Bug #10001]')
  end

  def local_variables_of(bind)
    this_should_not_be_in_bind = this_should_not_be_in_bind = 2
    bind.local_variables
  end

  def test_local_variables_in_other_context
    feature8773 = '[Feature #8773]'
    assert_equal([:feature8773], local_variables_of(binding), feature8773)
  end

  def test_local_variable_get
    b = get_binding
    assert_equal(0, b.local_variable_get(:a))
    assert_raise(NameError){ b.local_variable_get(:b) }

    # access keyword named local variables
    assert_equal(1, b.local_variable_get(:if))
    assert_equal(2, b.local_variable_get(:case))
    assert_equal(3, b.local_variable_get(:when))
    assert_equal(4, b.local_variable_get(:begin))
    assert_equal(5, b.local_variable_get(:end))

    assert_raise_with_message(NameError, /local variable \Wdefault\W/) {
      binding.local_variable_get(:default)
    }
  end

  def test_local_variable_set
    b = get_binding
    b.local_variable_set(:a, 10)
    b.local_variable_set(:b, 20)
    assert_equal(10, b.local_variable_get(:a))
    assert_equal(20, b.local_variable_get(:b))
    assert_equal(10, b.eval("a"))
    assert_equal(20, b.eval("b"))
  end

  def test_numparam_is_not_local_variables
    "foo".tap do
      _9 and flunk
      assert_equal([], binding.local_variables)
      assert_raise(NameError) { binding.local_variable_get(:_9) }
      assert_raise(NameError) { binding.local_variable_set(:_9, 1) }
      assert_raise(NameError) { binding.local_variable_defined?(:_9) }
      "bar".tap do
        assert_equal([], binding.local_variables)
        assert_raise(NameError) { binding.local_variable_get(:_9) }
        assert_raise(NameError) { binding.local_variable_set(:_9, 1) }
        assert_raise(NameError) { binding.local_variable_defined?(:_9) }
      end
      assert_equal([], binding.local_variables)
      assert_raise(NameError) { binding.local_variable_get(:_9) }
      assert_raise(NameError) { binding.local_variable_set(:_9, 1) }
      assert_raise(NameError) { binding.local_variable_defined?(:_9) }
    end

    "foo".tap do
      assert_equal([], binding.local_variables)
      assert_raise(NameError) { binding.local_variable_get(:_9) }
      assert_raise(NameError) { binding.local_variable_set(:_9, 1) }
      assert_raise(NameError) { binding.local_variable_defined?(:_9) }
      "bar".tap do
        _9 and flunk
        assert_equal([], binding.local_variables)
        assert_raise(NameError) { binding.local_variable_get(:_9) }
        assert_raise(NameError) { binding.local_variable_set(:_9, 1) }
        assert_raise(NameError) { binding.local_variable_defined?(:_9) }
      end
      assert_equal([], binding.local_variables)
      assert_raise(NameError) { binding.local_variable_get(:_9) }
      assert_raise(NameError) { binding.local_variable_set(:_9, 1) }
      assert_raise(NameError) { binding.local_variable_defined?(:_9) }
    end
  end

  def test_implicit_parameters_for_numparams
    x = x = 1
    assert_raise(NameError) { binding.implicit_parameter_get(:x) }
    assert_raise(NameError) { binding.implicit_parameter_defined?(:x) }

    "foo".tap do
      _5 and flunk
      assert_equal([:_1, :_2, :_3, :_4, :_5], binding.implicit_parameters)
      assert_equal("foo", binding.implicit_parameter_get(:_1))
      assert_equal(nil, binding.implicit_parameter_get(:_5))
      assert_raise(NameError) { binding.implicit_parameter_get(:_6) }
      assert_raise(NameError) { binding.implicit_parameter_get(:it) }
      assert_equal(true, binding.implicit_parameter_defined?(:_1))
      assert_equal(true, binding.implicit_parameter_defined?(:_5))
      assert_equal(false, binding.implicit_parameter_defined?(:_6))
      assert_equal(false, binding.implicit_parameter_defined?(:it))
      "bar".tap do
        assert_equal([], binding.implicit_parameters)
        assert_raise(NameError) { binding.implicit_parameter_get(:_1) }
        assert_raise(NameError) { binding.implicit_parameter_get(:_6) }
        assert_raise(NameError) { binding.implicit_parameter_get(:it) }
        assert_equal(false, binding.implicit_parameter_defined?(:_1))
        assert_equal(false, binding.implicit_parameter_defined?(:_6))
        assert_equal(false, binding.implicit_parameter_defined?(:it))
      end
      assert_equal([:_1, :_2, :_3, :_4, :_5], binding.implicit_parameters)
      assert_equal("foo", binding.implicit_parameter_get(:_1))
      assert_equal(nil, binding.implicit_parameter_get(:_5))
      assert_raise(NameError) { binding.implicit_parameter_get(:_6) }
      assert_raise(NameError) { binding.implicit_parameter_get(:it) }
      assert_equal(true, binding.implicit_parameter_defined?(:_1))
      assert_equal(true, binding.implicit_parameter_defined?(:_5))
      assert_equal(false, binding.implicit_parameter_defined?(:_6))
      assert_equal(false, binding.implicit_parameter_defined?(:it))
    end

    "foo".tap do
      assert_equal([], binding.implicit_parameters)
      assert_raise(NameError) { binding.implicit_parameter_get(:_1) }
      assert_raise(NameError) { binding.implicit_parameter_get(:_6) }
      assert_equal(false, binding.implicit_parameter_defined?(:_1))
      assert_equal(false, binding.implicit_parameter_defined?(:_6))
      assert_equal(false, binding.implicit_parameter_defined?(:it))
      "bar".tap do
        _5 and flunk
        assert_equal([:_1, :_2, :_3, :_4, :_5], binding.implicit_parameters)
        assert_equal("bar", binding.implicit_parameter_get(:_1))
        assert_equal(nil, binding.implicit_parameter_get(:_5))
        assert_raise(NameError) { binding.implicit_parameter_get(:_6) }
        assert_raise(NameError) { binding.implicit_parameter_get(:it) }
        assert_equal(true, binding.implicit_parameter_defined?(:_1))
        assert_equal(true, binding.implicit_parameter_defined?(:_5))
        assert_equal(false, binding.implicit_parameter_defined?(:_6))
        assert_equal(false, binding.implicit_parameter_defined?(:it))
      end
      assert_equal([], binding.implicit_parameters)
      assert_raise(NameError) { binding.implicit_parameter_get(:_1) }
      assert_raise(NameError) { binding.implicit_parameter_get(:_6) }
      assert_equal(false, binding.implicit_parameter_defined?(:_1))
      assert_equal(false, binding.implicit_parameter_defined?(:_6))
      assert_equal(false, binding.implicit_parameter_defined?(:it))
    end
  end

  def test_it_is_not_local_variable
    "foo".tap do
      it
      assert_equal([], binding.local_variables)
      assert_raise(NameError) { binding.local_variable_get(:it) }
      assert_equal(false, binding.local_variable_defined?(:it))
      "bar".tap do
        assert_equal([], binding.local_variables)
        assert_raise(NameError) { binding.local_variable_get(:it) }
        assert_equal(false, binding.local_variable_defined?(:it))
      end
      assert_equal([], binding.local_variables)
      assert_raise(NameError) { binding.local_variable_get(:it) }
      assert_equal(false, binding.local_variable_defined?(:it))
      "bar".tap do
        it
        assert_equal([], binding.local_variables)
        assert_raise(NameError) { binding.local_variable_get(:it) }
        assert_equal(false, binding.local_variable_defined?(:it))
      end
      assert_equal([], binding.local_variables)
      assert_raise(NameError) { binding.local_variable_get(:it) }
      assert_equal(false, binding.local_variable_defined?(:it))
    end

    "foo".tap do
      assert_equal([], binding.local_variables)
      assert_raise(NameError) { binding.local_variable_get(:it) }
      assert_equal(false, binding.local_variable_defined?(:it))
      "bar".tap do
        it
        assert_equal([], binding.local_variables)
        assert_raise(NameError) { binding.local_variable_get(:it) }
        assert_equal(false, binding.local_variable_defined?(:it))
      end
      assert_equal([], binding.local_variables)
      assert_raise(NameError) { binding.local_variable_get(:it) }
      assert_equal(false, binding.local_variable_defined?(:it))
    end
  end

  def test_implicit_parameters_for_it
    "foo".tap do
      it or flunk
      assert_equal([:it], binding.implicit_parameters)
      assert_equal("foo", binding.implicit_parameter_get(:it))
      assert_raise(NameError) { binding.implicit_parameter_get(:_1) }
      assert_equal(true, binding.implicit_parameter_defined?(:it))
      assert_equal(false, binding.implicit_parameter_defined?(:_1))
      "bar".tap do
        assert_equal([], binding.implicit_parameters)
        assert_raise(NameError) { binding.implicit_parameter_get(:it) }
        assert_raise(NameError) { binding.implicit_parameter_get(:_1) }
        assert_equal(false, binding.implicit_parameter_defined?(:it))
        assert_equal(false, binding.implicit_parameter_defined?(:_1))
      end
      assert_equal([:it], binding.implicit_parameters)
      assert_equal("foo", binding.implicit_parameter_get(:it))
      assert_raise(NameError) { binding.implicit_parameter_get(:_1) }
      assert_equal(true, binding.implicit_parameter_defined?(:it))
      assert_equal(false, binding.implicit_parameter_defined?(:_1))
    end

    "foo".tap do
      assert_equal([], binding.implicit_parameters)
      assert_raise(NameError) { binding.implicit_parameter_get(:it) }
      assert_raise(NameError) { binding.implicit_parameter_get(:_1) }
      assert_equal(false, binding.implicit_parameter_defined?(:it))
      assert_equal(false, binding.implicit_parameter_defined?(:_1))
      "bar".tap do
        it or flunk
        assert_equal([:it], binding.implicit_parameters)
        assert_equal("bar", binding.implicit_parameter_get(:it))
        assert_raise(NameError) { binding.implicit_parameter_get(:_1) }
        assert_equal(true, binding.implicit_parameter_defined?(:it))
        assert_equal(false, binding.implicit_parameter_defined?(:_1))
      end
      assert_equal([], binding.implicit_parameters)
      assert_raise(NameError) { binding.implicit_parameter_get(:it) }
      assert_raise(NameError) { binding.implicit_parameter_get(:_1) }
      assert_equal(false, binding.implicit_parameter_defined?(:it))
      assert_equal(false, binding.implicit_parameter_defined?(:_1))
    end
  end

  def test_implicit_parameters_for_it_complex
    "foo".tap do
      it = it = "bar"

      assert_equal([], binding.implicit_parameters)
      assert_raise(NameError) { binding.implicit_parameter_get(:it) }
      assert_equal(false, binding.implicit_parameter_defined?(:it))

      assert_equal([:it], binding.local_variables)
      assert_equal("bar", binding.local_variable_get(:it))
      assert_equal(true, binding.local_variable_defined?(:it))
    end

    "foo".tap do
      it or flunk

      assert_equal([:it], binding.implicit_parameters)
      assert_equal("foo", binding.implicit_parameter_get(:it))
      assert_equal(true, binding.implicit_parameter_defined?(:it))

      assert_equal([], binding.local_variables)
      assert_raise(NameError) { binding.local_variable_get(:it) }
      assert_equal(false, binding.local_variable_defined?(:it))
    end

    "foo".tap do
      it or flunk
      it = it = "bar"

      assert_equal([:it], binding.implicit_parameters)
      assert_equal("foo", binding.implicit_parameter_get(:it))
      assert_equal(true, binding.implicit_parameter_defined?(:it))

      assert_equal([:it], binding.local_variables)
      assert_equal("bar", binding.local_variable_get(:it))
      assert_equal(true, binding.local_variable_defined?(:it))
    end
  end

  def test_implicit_parameters_for_it_and_numparams
    "foo".tap do
      it or flunk
      "bar".tap do
        _5 and flunk
        assert_equal([:_1, :_2, :_3, :_4, :_5], binding.implicit_parameters)
        assert_raise(NameError) { binding.implicit_parameter_get(:it) }
        assert_equal("bar", binding.implicit_parameter_get(:_1))
        assert_equal(nil, binding.implicit_parameter_get(:_5))
        assert_raise(NameError) { binding.implicit_parameter_get(:_6) }
        assert_equal(false, binding.implicit_parameter_defined?(:it))
        assert_equal(true, binding.implicit_parameter_defined?(:_1))
        assert_equal(true, binding.implicit_parameter_defined?(:_5))
        assert_equal(false, binding.implicit_parameter_defined?(:_6))
      end
    end

    "foo".tap do
      _5 and flunk
      "bar".tap do
        it or flunk
        assert_equal([:it], binding.implicit_parameters)
        assert_equal("bar", binding.implicit_parameter_get(:it))
        assert_raise(NameError) { binding.implicit_parameter_get(:_1) }
        assert_raise(NameError) { binding.implicit_parameter_get(:_5) }
        assert_raise(NameError) { binding.implicit_parameter_get(:_6) }
        assert_equal(true, binding.implicit_parameter_defined?(:it))
        assert_equal(false, binding.implicit_parameter_defined?(:_1))
        assert_equal(false, binding.implicit_parameter_defined?(:_5))
        assert_equal(false, binding.implicit_parameter_defined?(:_6))
      end
    end
  end

  def test_implicit_parameter_invalid_name
    message_pattern = /is not an implicit parameter/
    assert_raise_with_message(NameError, message_pattern) { binding.implicit_parameter_defined?(:foo) }
    assert_raise_with_message(NameError, message_pattern) { binding.implicit_parameter_get(:foo) }
    assert_raise_with_message(NameError, message_pattern) { binding.implicit_parameter_defined?("wrong_implicit_parameter_name_#{rand(10000)}") }
    assert_raise_with_message(NameError, message_pattern) { binding.implicit_parameter_get("wrong_implicit_parameter_name_#{rand(10000)}") }
  end

  def test_local_variable_set_wb
    assert_ruby_status([], <<-'end;', '[Bug #13605]', timeout: 30)
      b = binding
      n = 20_000

      n.times do |i|
        v = rand(2_000)
        name = "n#{v}"
        value = Object.new
        b.local_variable_set name, value
      end
    end;
  end

  def test_local_variable_defined?
    b = get_binding
    assert_equal(true, b.local_variable_defined?(:a))
    assert_equal(false, b.local_variable_defined?(:b))
  end

  def test_binding_receiver
    feature8779 = '[ruby-dev:47613] [Feature #8779]'

    assert_same(self, binding.receiver, feature8779)

    obj = Object.new
    def obj.b; binding; end
    assert_same(obj, obj.b.receiver, feature8779)
  end

  def test_proc_mark
    assert_normal_exit(<<-'EOS')
      def f
        Enumerator.new{
          100000.times {|i|
            yield
            s = "#{i}"
          }
        }
      end

      def g
        x = proc{}
        f(&x)
      end
      e = g
      e.each {}
    EOS
  end

  def test_prepended_call
    assert_in_out_err([], "#{<<~"begin;"}\n#{<<~'end;'}", ["call"])
    begin;
      Proc.prepend Module.new {def call() puts "call"; super; end}
      def m(&blk) blk.call; end
      m {}
    end;
  end

  def test_refined_call
    assert_in_out_err([], "#{<<~"begin;"}\n#{<<~'end;'}", ["call"])
    begin;
      using Module.new {refine(Proc) {def call() puts "call"; super; end}}
      def m(&blk) blk.call; end
      m {}
    end;
  end

  def test_compose
    f = proc {|x| x * 2}
    g = proc {|x| x + 1}

    assert_equal(6, (f << g).call(2))
    assert_equal(6, (g >> f).call(2))
  end

  def test_compose_with_multiple_args
    f = proc {|x| x * 2}
    g = proc {|x, y| x + y}

    assert_equal(6, (f << g).call(1, 2))
    assert_equal(6, (g >> f).call(1, 2))
  end

  def test_compose_with_block
    f = proc {|x| x * 2}
    g = proc {|&blk| blk.call(1) }

    assert_equal(8, (f << g).call { |x| x + 3 })
    assert_equal(8, (g >> f).call { |x| x + 3 })
  end

  def test_compose_with_lambda
    f = lambda {|x| x * 2}
    g = lambda {|x| x}
    not_lambda = proc {|x| x}

    assert_predicate((f << g), :lambda?)
    assert_predicate((g >> f), :lambda?)
    assert_predicate((not_lambda << f), :lambda?)
    assert_not_predicate((f << not_lambda), :lambda?)
    assert_not_predicate((not_lambda >> f), :lambda?)
  end

  def test_compose_with_method
    f = proc {|x| x * 2}
    c = Class.new {
      def g(x) x + 1 end
    }
    g = c.new.method(:g)

    assert_equal(6, (f << g).call(2))
    assert_equal(5, (f >> g).call(2))
    assert_predicate((f << g), :lambda?)
  end

  def test_compose_with_callable
    f = proc {|x| x * 2}
    c = Class.new {
      def call(x) x + 1 end
    }
    g = c.new

    assert_equal(6, (f << g).call(2))
    assert_equal(5, (f >> g).call(2))
    assert_predicate((f << g), :lambda?)
  end

  def test_compose_with_noncallable
    f = proc {|x| x * 2}

    assert_raise(TypeError) {
      (f << 5).call(2)
    }
    assert_raise(TypeError) {
      (f >> 5).call(2)
    }
  end

  def test_orphan_return
    assert_equal(42, Module.new { extend self
      def m1(&b) b.call end; def m2(); m1 { return 42 } end }.m2)
    assert_equal(42, Module.new { extend self
      def m1(&b) b end; def m2(); m1 { return 42 }.call end }.m2)
    assert_raise(LocalJumpError) { Module.new { extend self
      def m1(&b) b end; def m2(); m1 { return 42 } end }.m2.call }
  end

  def test_orphan_break
    assert_equal(42, Module.new { extend self
      def m1(&b) b.call end; def m2(); m1 { break 42 } end }.m2 )
    assert_raise(LocalJumpError) { Module.new { extend self
      def m1(&b) b end; def m2(); m1 { break 42 }.call end }.m2 }
    assert_raise(LocalJumpError) { Module.new { extend self
      def m1(&b) b end; def m2(); m1 { break 42 } end }.m2.call }
  end

  def test_not_orphan_next
    assert_equal(42, Module.new { extend self
      def m1(&b) b.call end; def m2(); m1 { next 42 } end }.m2)
    assert_equal(42, Module.new { extend self
      def m1(&b) b end; def m2(); m1 { next 42 }.call end }.m2)
    assert_equal(42, Module.new { extend self
      def m1(&b) b end; def m2(); m1 { next 42 } end }.m2.call)
  end

  def test_isolate
    assert_raise_with_message ArgumentError, /\(a\)/ do
      a = :a
      Proc.new{p a}.isolate
    end

    assert_raise_with_message ArgumentError, /\(a\)/ do
      a = :a
      1.times{
        Proc.new{p a}.isolate
      }
    end

    assert_raise_with_message ArgumentError, /yield/ do
      Proc.new{yield}.isolate
    end


    name = "\u{2603 26a1}"
    assert_raise_with_message(ArgumentError, /\(#{name}\)/) do
      eval("#{name} = :#{name}; Proc.new {p #{name}}").isolate
    end

    # binding

    :a.tap{|a|
      :b.tap{|b|
        Proc.new{
          :c.tap{|c|
            assert_equal :c, eval('c')

            assert_raise_with_message SyntaxError, /\`a\'/ do
              eval('p a')
            end

            assert_raise_with_message SyntaxError, /\`b\'/ do
              eval('p b')
            end

            assert_raise_with_message SyntaxError, /can not yield from isolated Proc/ do
              eval('p yield')
            end

            assert_equal :c, binding.local_variable_get(:c)

            assert_raise_with_message NameError, /local variable \`a\' is not defined/ do
              binding.local_variable_get(:a)
            end

            assert_equal [:c], local_variables
            assert_equal [:c], binding.local_variables
          }
        }.isolate.call
      }
    }
  end if proc{}.respond_to? :isolate
end

class TestProcKeywords < Test::Unit::TestCase
  def test_compose_keywords
    f = ->(**kw) { kw.merge(:a=>1) }
    g = ->(kw) { kw.merge(:a=>2) }

    assert_equal(2, (f >> g).call(a: 3)[:a])
    assert_raise(ArgumentError) { (f << g).call(a: 3)[:a] }
    assert_equal(2, (f >> g).call(a: 3)[:a])
    assert_raise(ArgumentError) { (f << g).call({a: 3})[:a] }
    assert_raise(ArgumentError) { (f >> g).call({a: 3})[:a] }
    assert_equal(2, (g << f).call(a: 3)[:a])
    assert_raise(ArgumentError) { (g >> f).call(a: 3)[:a] }
    assert_raise(ArgumentError) { (g << f).call({a: 3})[:a] }
    assert_raise(ArgumentError) { (g >> f).call({a: 3})[:a] }
    assert_raise(ArgumentError) { (f << g).call(**{})[:a] }
    assert_equal(2, (f >> g).call(**{})[:a])
  end

  def test_compose_keywords_method
    f = ->(**kw) { kw.merge(:a=>1) }.method(:call)
    g = ->(kw) { kw.merge(:a=>2) }.method(:call)

    assert_raise(ArgumentError) { (f << g).call(a: 3)[:a] }
    assert_equal(2, (f >> g).call(a: 3)[:a])
    assert_raise(ArgumentError) { (f << g).call({a: 3})[:a] }
    assert_raise(ArgumentError) { (f >> g).call({a: 3})[:a] }
    assert_equal(2, (g << f).call(a: 3)[:a])
    assert_raise(ArgumentError) { (g >> f).call(a: 3)[:a] }
    assert_raise(ArgumentError) { (g << f).call({a: 3})[:a] }
    assert_raise(ArgumentError) { (g >> f).call({a: 3})[:a] }
    assert_raise(ArgumentError) { (f << g).call(**{})[:a] }
    assert_equal(2, (f >> g).call(**{})[:a])
  end

  def test_compose_keywords_non_proc
    f = ->(**kw) { kw.merge(:a=>1) }
    g = Object.new
    def g.call(kw) kw.merge(:a=>2) end
    def g.to_proc; method(:call).to_proc; end
    def g.<<(f) to_proc << f end
    def g.>>(f) to_proc >> f end

    assert_raise(ArgumentError) { (f << g).call(a: 3)[:a] }
    assert_equal(2, (f >> g).call(a: 3)[:a])
    assert_raise(ArgumentError) { (f << g).call({a: 3})[:a] }
    assert_raise(ArgumentError) { (f >> g).call({a: 3})[:a] }
    assert_equal(2, (g << f).call(a: 3)[:a])
    assert_raise(ArgumentError) { (g >> f).call(a: 3)[:a] }
    assert_raise(ArgumentError) { (g << f).call({a: 3})[:a] }
    assert_raise(ArgumentError) { (g >> f).call({a: 3})[:a] }
    assert_raise(ArgumentError) { (f << g).call(**{})[:a] }
    assert_equal(2, (f >> g).call(**{})[:a])

    f = ->(kw) { kw.merge(:a=>1) }
    g = Object.new
    def g.call(**kw) kw.merge(:a=>2) end
    def g.to_proc; method(:call).to_proc; end
    def g.<<(f) to_proc << f end
    def g.>>(f) to_proc >> f end

    assert_equal(1, (f << g).call(a: 3)[:a])
    assert_raise(ArgumentError) { (f >> g).call(a: 3)[:a] }
    assert_raise(ArgumentError) { (f << g).call({a: 3})[:a] }
    assert_raise(ArgumentError) { (f >> g).call({a: 3})[:a] }
    assert_raise(ArgumentError) { (g << f).call(a: 3)[:a] }
    assert_equal(1, (g >> f).call(a: 3)[:a])
    assert_raise(ArgumentError) { (g << f).call({a: 3})[:a] }
    assert_raise(ArgumentError) { (g >> f).call({a: 3})[:a] }
    assert_equal(1, (f << g).call(**{})[:a])
    assert_raise(ArgumentError) { (f >> g).call(**{})[:a] }
  end
end
