# frozen_string_literal: false
require 'test/unit'

class TestSymbol < Test::Unit::TestCase
  # [ruby-core:3573]

  def assert_eval_inspected(sym, valid = true)
    n = sym.inspect
    if valid
      bug5136 = '[ruby-dev:44314]'
      assert_not_match(/\A:"/, n, bug5136)
    end
    assert_nothing_raised(SyntaxError) {assert_equal(sym, eval(n))}
  end

  def test_intern
    assert_equal(':""', ''.intern.inspect)
    assert_equal(':$foo', '$foo'.intern.inspect)
    assert_equal(':"!foo"', '!foo'.intern.inspect)
    assert_equal(':"foo=="', "foo==".intern.inspect)
  end

  def test_all_symbols
    x = Symbol.all_symbols
    assert_kind_of(Array, x)
    assert_empty(x.reject {|s| s.is_a?(Symbol) })
  end

  def test_inspect_invalid
    # 2) Symbol#inspect sometimes returns invalid symbol representations:
    assert_eval_inspected(:"!")
    assert_eval_inspected(:"=", false)
    assert_eval_inspected(:"0", false)
    assert_eval_inspected(:"$1")
    assert_eval_inspected(:"@1", false)
    assert_eval_inspected(:"@@1", false)
    assert_eval_inspected(:"@", false)
    assert_eval_inspected(:"@@", false)
    assert_eval_inspected(:"[]=")
    assert_eval_inspected(:"[][]", false)
    assert_eval_inspected(:"[][]=", false)
    assert_eval_inspected(:"@=", false)
    assert_eval_inspected(:"@@=", false)
    assert_eval_inspected(:"@x=", false)
    assert_eval_inspected(:"@@x=", false)
    assert_eval_inspected(:"$$=", false)
    assert_eval_inspected(:"$==", false)
    assert_eval_inspected(:"$x=", false)
    assert_eval_inspected(:"$$$=", false)
    assert_eval_inspected(:"foo?=", false)
    assert_eval_inspected(:"foo!=", false)
  end

  def assert_inspect_evaled(n)
    assert_nothing_raised(SyntaxError) {assert_equal(n, eval(n).inspect)}
  end

  def test_inspect_suboptimal
    # 3) Symbol#inspect sometimes returns suboptimal symbol representations:
    assert_inspect_evaled(':foo')
    assert_inspect_evaled(':foo!')
    assert_inspect_evaled(':bar?')
    assert_inspect_evaled(":<<")
    assert_inspect_evaled(':>>')
    assert_inspect_evaled(':<=')
    assert_inspect_evaled(':>=')
    assert_inspect_evaled(':=~')
    assert_inspect_evaled(':==')
    assert_inspect_evaled(':===')
    assert_raise(SyntaxError) {eval ':='}
    assert_inspect_evaled(':*')
    assert_inspect_evaled(':**')
    assert_raise(SyntaxError) {eval ':***'}
    assert_inspect_evaled(':+')
    assert_inspect_evaled(':-')
    assert_inspect_evaled(':+@')
    assert_inspect_evaled(':-@')
    assert_inspect_evaled(':|')
    assert_inspect_evaled(':^')
    assert_inspect_evaled(':&')
    assert_inspect_evaled(':/')
    assert_inspect_evaled(':%')
    assert_inspect_evaled(':~')
    assert_inspect_evaled(':`')
    assert_inspect_evaled(':[]')
    assert_inspect_evaled(':[]=')
    assert_raise(SyntaxError) {eval ':||'}
    assert_raise(SyntaxError) {eval ':&&'}
    assert_raise(SyntaxError) {eval ':['}
  end

  def test_inspect_dollar
    # 4) :$- always treats next character literally:
    assert_raise(SyntaxError) {eval ':$-'}
    assert_raise(SyntaxError) {eval ":$-\n"}
    assert_raise(SyntaxError) {eval ":$- "}
    assert_raise(SyntaxError) {eval ":$-#"}
    assert_raise(SyntaxError) {eval ':$-('}
  end

  def test_inspect_number
    # 5) Inconsistency between :$0 and :$1? The first one is valid, but the
    # latter isn't.
    assert_inspect_evaled(':$0')
    assert_inspect_evaled(':$1')
  end

  def test_inspect
    valid = %W{$a @a @@a < << <= <=> > >> >= =~ == === * ** + +@ - -@
    | ^ & / % ~ \` [] []= ! != !~ a a? a! a= A A? A! A=}
    valid.each do |sym|
      assert_equal(':' + sym, sym.intern.inspect)
    end

    invalid = %w{$a? $a! $a= @a? @a! @a= @@a? @@a! @@a= =}
    invalid.each do |sym|
      assert_equal(':"' + sym + '"', sym.intern.inspect)
    end
  end

  def test_inspect_under_gc_compact_stress
    omit "compaction doesn't work well on s390x" if RUBY_PLATFORM =~ /s390x/ # https://github.com/ruby/ruby/pull/5077
    omit "very flaky on many platforms, more so with YJIT enabled" if defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
    omit "very flaky on many platforms, more so with RJIT enabled" if defined?(RubyVM::RJIT) && RubyVM::RJIT.enabled?
    EnvUtil.under_gc_compact_stress do
      assert_inspect_evaled(':testing')
    end
  end

  def test_name
    assert_equal("foo", :foo.name)
    assert_same(:foo.name, :foo.name)
    assert_predicate(:foo.name, :frozen?)
  end

  def test_to_proc
    assert_equal %w(1 2 3), (1..3).map(&:to_s)
    [
      [],
      [1],
      [1, 2],
      [1, [2, 3]],
    ].each do |ary|
      ary_id = ary.object_id
      assert_equal ary_id, :object_id.to_proc.call(ary)
      ary_ids = ary.collect{|x| x.object_id }
      assert_equal ary_ids, ary.collect(&:object_id)
    end
  end

  def test_to_proc_yield
    assert_ruby_status([], "#{<<-"begin;"}\n#{<<-"end;"}", timeout: 5.0)
    begin;
      GC.stress = true
      true.tap(&:itself)
    end;
  end

  def test_to_proc_new_proc
    assert_ruby_status([], "#{<<-"begin;"}\n#{<<-"end;"}", timeout: 5.0)
    begin;
      GC.stress = true
      2.times {Proc.new(&:itself)}
    end;
  end

  def test_to_proc_no_method
    assert_separately([], "#{<<-"begin;"}\n#{<<-"end;"}", timeout: 5.0)
    begin;
      bug11566 = '[ruby-core:70980] [Bug #11566]'
      assert_raise(NoMethodError, bug11566) {Proc.new(&:foo).(1)}
      assert_raise(NoMethodError, bug11566) {:foo.to_proc.(1)}
    end;
  end

  def test_to_proc_arg
    assert_separately([], "#{<<-"begin;"}\n#{<<-"end;"}", timeout: 5.0)
    begin;
      def (obj = Object.new).proc(&b) b; end
      assert_same(:itself.to_proc, obj.proc(&:itself))
    end;
  end

  def test_to_proc_lambda?
    assert_predicate(:itself.to_proc, :lambda?)
  end

  def test_to_proc_arity
    assert_equal(-2, :itself.to_proc.arity)
  end

  def test_to_proc_call_with_symbol_proc
    first = 1
    bug11594 = "[ruby-core:71088] [Bug #11594] corrupted the first local variable"
    # symbol which does not have a Proc
    ->(&blk) {}.call(&:test_to_proc_call_with_symbol_proc)
    assert_equal(1, first, bug11594)
  end

  class TestToPRocArgWithRefinements; end
  def _test_to_proc_arg_with_refinements_call(&block)
    block.call TestToPRocArgWithRefinements.new
  end
  def _test_to_proc_with_refinements_call(&block)
    block
  end
  using Module.new {
    refine TestToPRocArgWithRefinements do
      def hoge
        :hoge
      end
    end
  }
  def test_to_proc_arg_with_refinements
    assert_equal(:hoge, _test_to_proc_arg_with_refinements_call(&:hoge))
  end

  def test_to_proc_lambda_with_refinements
    assert_predicate(_test_to_proc_with_refinements_call(&:hoge), :lambda?)
  end

  def test_to_proc_arity_with_refinements
    assert_equal(-2, _test_to_proc_with_refinements_call(&:hoge).arity)
  end

  def self._test_to_proc_arg_with_refinements_call(&block)
    block.call TestToPRocArgWithRefinements.new
  end
  _test_to_proc_arg_with_refinements_call(&:hoge)
  using Module.new {
    refine TestToPRocArgWithRefinements do
      def hoge
        :hogehoge
      end
    end
  }
  def test_to_proc_arg_with_refinements_override
    assert_equal(:hogehoge, _test_to_proc_arg_with_refinements_call(&:hoge))
  end

  def test_to_proc_arg_with_refinements_undefined
    assert_raise(NoMethodError) do
      _test_to_proc_arg_with_refinements_call(&:foo)
    end
  end

  private def return_from_proc
    Proc.new { return 1 }.tap(&:call)
  end

  def test_return_from_symbol_proc
    bug12462 = '[ruby-core:75856] [Bug #12462]'
    assert_equal(1, return_from_proc, bug12462)
  end

  def test_to_proc_for_hash_each
    bug11830 = '[ruby-core:72205] [Bug #11830]'
    assert_normal_exit("#{<<-"begin;"}\n#{<<-'end;'}", bug11830)
    begin;
      {}.each(&:destroy)
    end;
  end

  def test_to_proc_iseq
    assert_separately([], "#{<<-"begin;"}\n#{<<~"end;"}", timeout: 5)
    begin;
      bug11845 = '[ruby-core:72381] [Bug #11845]'
      assert_nil(:class.to_proc.source_location, bug11845)
      assert_equal([[:req], [:rest]], :class.to_proc.parameters, bug11845)
      c = Class.new {define_method(:klass, :class.to_proc)}
      m = c.instance_method(:klass)
      assert_nil(m.source_location, bug11845)
      assert_equal([[:req], [:rest]], m.parameters, bug11845)
    end;
  end

  def test_to_proc_binding
    assert_separately([], "#{<<-"begin;"}\n#{<<~"end;"}", timeout: 5)
    begin;
      bug12137 = '[ruby-core:74100] [Bug #12137]'
      assert_raise(ArgumentError, bug12137) {
        :succ.to_proc.binding
      }
    end;
  end

  def test_to_proc_instance_exec
    bug = '[ruby-core:78839] [Bug #13074] should evaluate on the argument'
    assert_equal(2, BasicObject.new.instance_exec(1, &:succ), bug)
    assert_equal(3, BasicObject.new.instance_exec(1, 2, &:+), bug)
  end

  def test_call
    o = Object.new
    def o.foo(x, y); x + y; end

    assert_equal(3, :foo.to_proc.call(o, 1, 2))
    assert_raise(ArgumentError) { :foo.to_proc.call }
  end

  def m_block_given?
    block_given?
  end

  def m2_block_given?(m = nil)
    if m
      [block_given?, m.call(self)]
    else
      block_given?
    end
  end

  def test_block_given_to_proc
    bug8531 = '[Bug #8531]'
    m = :m_block_given?.to_proc
    assert(!m.call(self), "#{bug8531} without block")
    assert(m.call(self) {}, "#{bug8531} with block")
    assert(!m.call(self), "#{bug8531} without block second")
  end

  def test_block_persist_between_calls
    bug8531 = '[Bug #8531]'
    m2 = :m2_block_given?.to_proc
    assert_equal([true, false], m2.call(self, m2) {}, "#{bug8531} nested with block")
    assert_equal([false, false], m2.call(self, m2), "#{bug8531} nested without block")
  end

  def test_block_curry_proc
    assert_separately([], "#{<<-"begin;"}\n#{<<-"end;"}")
    begin;
    b = proc { true }.curry
    assert(b.call, "without block")
    assert(b.call { |o| o.to_s }, "with block")
    assert(b.call(&:to_s), "with sym block")
    end;
  end

  def test_block_curry_lambda
    assert_separately([], "#{<<-"begin;"}\n#{<<-"end;"}")
    begin;
    b = lambda { true }.curry
    assert(b.call, "without block")
    assert(b.call { |o| o.to_s }, "with block")
    assert(b.call(&:to_s), "with sym block")
    end;
  end

  def test_block_method_to_proc
    assert_separately([], "#{<<-"begin;"}\n#{<<-"end;"}")
    begin;
    b = method(:tap).to_proc
    assert(b.call { |o| o.to_s }, "with block")
    assert(b.call(&:to_s), "with sym block")
    end;
  end

  def test_succ
    assert_equal(:fop, :foo.succ)
  end

  def test_cmp
    assert_equal(0, :FoO <=> :FoO)
    assert_equal(-1, :FoO <=> :fOO)
    assert_equal(1, :fOO <=> :FoO)
    assert_nil(:foo <=> "foo")
  end

  def test_casecmp
    assert_equal(0, :FoO.casecmp(:fOO))
    assert_equal(1, :FoO.casecmp(:BaR))
    assert_equal(-1, :baR.casecmp(:FoO))

    assert_nil(:foo.casecmp("foo"))
    assert_nil(:foo.casecmp(Object.new))
  end

  def test_casecmp?
    assert_equal(true, :FoO.casecmp?(:fOO))
    assert_equal(false, :FoO.casecmp?(:BaR))
    assert_equal(false, :baR.casecmp?(:FoO))
    assert_equal(true, :äöü.casecmp?(:ÄÖÜ))

    assert_nil(:foo.casecmp?("foo"))
    assert_nil(:foo.casecmp?(Object.new))
  end

  def test_length
    assert_equal(3, :FoO.length)
    assert_equal(3, :FoO.size)
  end

  def test_empty
    assert_equal(false, :FoO.empty?)
    assert_equal(true, :"".empty?)
  end

  def test_case
    assert_equal(:FOO, :FoO.upcase)
    assert_equal(:foo, :FoO.downcase)
    assert_equal(:Foo, :foo.capitalize)
    assert_equal(:fOo, :FoO.swapcase)
  end

  def test_MATCH # '=~'
    assert_equal(10,  :"FeeFieFoo-Fum" =~ /Fum$/)
    assert_equal(nil, "FeeFieFoo-Fum" =~ /FUM$/)

    o = Object.new
    def o.=~(x); x + "bar"; end
    assert_equal("foobar", :"foo" =~ o)

    assert_raise(TypeError) { :"foo" =~ "foo" }
  end

  def test_match_method
    assert_equal("bar", :"foobarbaz".match(/bar/).to_s)

    o = Regexp.new('foo')
    def o.match(x, y, z); x + y + z; end
    assert_equal("foobarbaz", :"foo".match(o, "bar", "baz"))
    x = nil
    :"foo".match(o, "bar", "baz") {|y| x = y }
    assert_equal("foobarbaz", x)

    assert_raise(ArgumentError) { :"foo".match }
  end

  def test_match_p_regexp
    /backref/ =~ 'backref'
    # must match here, but not in a separate method, e.g., assert_send,
    # to check if $~ is affected or not.
    assert_equal(true, "".match?(//))
    assert_equal(true, :abc.match?(/.../))
    assert_equal(true, 'abc'.match?(/b/))
    assert_equal(true, 'abc'.match?(/b/, 1))
    assert_equal(true, 'abc'.match?(/../, 1))
    assert_equal(true, 'abc'.match?(/../, -2))
    assert_equal(false, 'abc'.match?(/../, -4))
    assert_equal(false, 'abc'.match?(/../, 4))
    assert_equal(true, ("\u3042" + '\x').match?(/../, 1))
    assert_equal(true, ''.match?(/\z/))
    assert_equal(true, 'abc'.match?(/\z/))
    assert_equal(true, 'Ruby'.match?(/R.../))
    assert_equal(false, 'Ruby'.match?(/R.../, 1))
    assert_equal(false, 'Ruby'.match?(/P.../))
    assert_equal('backref', $&)
  end

  def test_match_p_string
    /backref/ =~ 'backref'
    # must match here, but not in a separate method, e.g., assert_send,
    # to check if $~ is affected or not.
    assert_equal(true, "".match?(''))
    assert_equal(true, :abc.match?('...'))
    assert_equal(true, 'abc'.match?('b'))
    assert_equal(true, 'abc'.match?('b', 1))
    assert_equal(true, 'abc'.match?('..', 1))
    assert_equal(true, 'abc'.match?('..', -2))
    assert_equal(false, 'abc'.match?('..', -4))
    assert_equal(false, 'abc'.match?('..', 4))
    assert_equal(true, ("\u3042" + '\x').match?('..', 1))
    assert_equal(true, ''.match?('\z'))
    assert_equal(true, 'abc'.match?('\z'))
    assert_equal(true, 'Ruby'.match?('R...'))
    assert_equal(false, 'Ruby'.match?('R...', 1))
    assert_equal(false, 'Ruby'.match?('P...'))
    assert_equal('backref', $&)
  end

  def test_symbol_popped
    assert_nothing_raised { eval('a = 1; :"#{ a }"; 1') }
  end

  def test_ascii_incomat_inspect
    [Encoding::UTF_16LE, Encoding::UTF_16BE,
     Encoding::UTF_32LE, Encoding::UTF_32BE].each do |e|
      assert_equal(':"abc"', "abc".encode(e).to_sym.inspect)
      assert_equal(':"\\u3042\\u3044\\u3046"', "\u3042\u3044\u3046".encode(e).to_sym.inspect)
    end
  end

  def test_symbol_encoding
    assert_equal(Encoding::US_ASCII, "$-A".force_encoding("iso-8859-15").intern.encoding)
    assert_equal(Encoding::US_ASCII, "foobar~!".force_encoding("iso-8859-15").intern.encoding)
    assert_equal(Encoding::UTF_8, "\u{2192}".intern.encoding)
    assert_raise_with_message(EncodingError, /\\xb0/i) {"\xb0a".force_encoding("utf-8").intern}
  end

  def test_singleton_method
    assert_raise(TypeError) { a = :foo; def a.foo; end }
  end

  SymbolsForEval = [
    :foo,
    "dynsym_#{Random.rand(10000)}_#{Time.now}".to_sym
  ]

  def test_instance_eval
    bug11086 = '[ruby-core:68961] [Bug #11086]'
    SymbolsForEval.each do |sym|
      assert_nothing_raised(TypeError, sym, bug11086) {
        sym.instance_eval {}
      }
      assert_raise(TypeError, sym, bug11086) {
        sym.instance_eval {def foo; end}
      }
    end
  end

  def test_instance_exec
    bug11086 = '[ruby-core:68961] [Bug #11086]'
    SymbolsForEval.each do |sym|
      assert_nothing_raised(TypeError, sym, bug11086) {
        sym.instance_exec {}
      }
      assert_raise(TypeError, sym, bug11086) {
        sym.instance_exec {def foo; end}
      }
    end
  end

  def test_frozen_symbol
    assert_equal(true, :foo.frozen?)
    assert_equal(true, :each.frozen?)
    assert_equal(true, :+.frozen?)
    assert_equal(true, "foo#{Time.now.to_i}".to_sym.frozen?)
    assert_equal(true, :foo.to_sym.frozen?)
  end

  def test_symbol_gc_1
    assert_normal_exit('".".intern;GC.start(immediate_sweep:false);eval %[GC.start;".".intern]',
                       '',
                       child_env: '--disable-gems')
    assert_normal_exit('".".intern;GC.start(immediate_sweep:false);eval %[GC.start;:"."]',
                       '',
                       child_env: '--disable-gems')
    assert_normal_exit('".".intern;GC.start(immediate_sweep:false);eval %[GC.start;%i"."]',
                       '',
                       child_env: '--disable-gems')
    assert_normal_exit('tap{".".intern};GC.start(immediate_sweep:false);' +
                       'eval %[syms=Symbol.all_symbols;GC.start;syms.each(&:to_sym)]',
                       '',
                       child_env: '--disable-gems')
  end

  def test_dynamic_attrset_id
    bug10259 = '[ruby-dev:48559] [Bug #10259]'
    class << (obj = Object.new)
      attr_writer :unagi
    end
    assert_nothing_raised(NoMethodError, bug10259) {obj.send("unagi=".intern, 1)}
  end

  def test_symbol_fstr_memory_leak
    bug10686 = '[ruby-core:67268] [Bug #10686]'
    assert_no_memory_leak([], "#{<<~"begin;"}\n#{<<~'else;'}", "#{<<~'end;'}", bug10686, limit: 1.71, rss: true, timeout: 20)
    begin;
      n = 100_000
      n.times { |i| i.to_s.to_sym }
    else;
      (2 * n).times { |i| (i + n).to_s.to_sym }
    end;
  end

  def test_hash_redefinition
    assert_separately([], "#{<<-"begin;"}\n#{<<-'end;'}")
    begin;
      bug11035 = '[ruby-core:68767] [Bug #11035]'
      class Symbol
        def hash
          raise
        end
      end

      h = {}
      assert_nothing_raised(RuntimeError, bug11035) {
        h[:foo] = 1
      }
      assert_nothing_raised(RuntimeError, bug11035) {
        h['bar'.to_sym] = 2
      }
    end;
  end

  def test_hash_nondeterministic
    ruby = EnvUtil.rubybin
    assert_not_equal :foo.hash, `#{ruby} -e 'puts :foo.hash'`.to_i,
                     '[ruby-core:80430] [Bug #13376]'

    sym = "dynsym_#{Random.rand(10000)}_#{Time.now}"
    assert_not_equal sym.to_sym.hash,
                     `#{ruby} -e 'puts #{sym.inspect}.to_sym.hash'`.to_i
  end

  def test_eq_can_be_redefined
    assert_in_out_err([], <<-RUBY, ["foo"], [])
      class Symbol
        remove_method :==
        def ==(obj)
          "foo"
        end
      end

      puts :a == :a
    RUBY
  end

  def test_start_with?
    assert_equal(true, :hello.start_with?("hel"))
    assert_equal(false, :hello.start_with?("el"))
    assert_equal(true, :hello.start_with?("el", "he"))

    bug5536 = '[ruby-core:40623]'
    assert_raise(TypeError, bug5536) {:str.start_with? :not_convertible_to_string}

    assert_equal(true, :hello.start_with?(/hel/))
    assert_equal("hel", $&)
    assert_equal(false, :hello.start_with?(/el/))
    assert_nil($&)
  end

  def test_end_with?
    assert_equal(true, :hello.end_with?("llo"))
    assert_equal(false, :hello.end_with?("ll"))
    assert_equal(true, :hello.end_with?("el", "lo"))

    bug5536 = '[ruby-core:40623]'
    assert_raise(TypeError, bug5536) {:str.end_with? :not_convertible_to_string}
  end
end
