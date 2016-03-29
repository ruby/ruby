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
    assert_ruby_status([], <<-"end;", timeout: 5.0)
      GC.stress = true
      true.tap(&:itself)
    end;
  end

  def test_to_proc_new_proc
    assert_ruby_status([], <<-"end;", timeout: 5.0)
      GC.stress = true
      2.times {Proc.new(&:itself)}
    end;
  end

  def test_to_proc_no_method
    assert_separately([], <<-"end;", timeout: 5.0)
      bug11566 = '[ruby-core:70980] [Bug #11566]'
      assert_raise(NoMethodError, bug11566) {Proc.new(&:foo).(1)}
      assert_raise(NoMethodError, bug11566) {:foo.to_proc.(1)}
    end;
  end

  def test_to_proc_arg
    assert_separately([], <<-"end;", timeout: 5.0)
      def (obj = Object.new).proc(&b) b; end
      assert_same(:itself.to_proc, obj.proc(&:itself))
    end;
  end

  def test_to_proc_call_with_symbol_proc
    first = 1
    bug11594 = "[ruby-core:71088] [Bug #11594] corrupted the first local variable"
    # symbol which does not have a Proc
    ->(&blk) {}.call(&:test_to_proc_call_with_symbol_proc)
    assert_equal(1, first, bug11594)
  end

  def test_to_proc_for_hash_each
    bug11830 = '[ruby-core:72205] [Bug #11830]'
    assert_normal_exit(<<-'end;', bug11830) # do
      {}.each(&:destroy)
    end;
  end

  def test_to_proc_iseq
    assert_separately([], <<~"end;", timeout: 1) # do
      bug11845 = '[ruby-core:72381] [Bug #11845]'
      assert_nil(:class.to_proc.source_location, bug11845)
      assert_equal([[:rest]], :class.to_proc.parameters, bug11845)
      c = Class.new {define_method(:klass, :class.to_proc)}
      m = c.instance_method(:klass)
      assert_nil(m.source_location, bug11845)
      assert_equal([[:rest]], m.parameters, bug11845)
    end;
  end

  def test_to_proc_binding
    assert_separately([], <<~"end;", timeout: 1) # do
      bug12137 = '[ruby-core:74100] [Bug #12137]'
      assert_raise(ArgumentError, bug12137) {
        :succ.to_proc.binding
      }
    end;
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

  def test_symbol_poped
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
    assert_raise(EncodingError) {"\xb0a".force_encoding("utf-8").intern}
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

  def test_symbol_fstr_leak
    bug10686 = '[ruby-core:67268] [Bug #10686]'
    x = 0
    assert_no_memory_leak([], '200_000.times { |i| i.to_s.to_sym }; GC.start', <<-"end;", bug10686, limit: 1.71, rss: true)
      200_000.times { |i| (i + 200_000).to_s.to_sym }
    end;
  end

  def test_hash_redefinition
    assert_separately([], <<-'end;')
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

  def test_not_freeze
    bug11721 = '[ruby-core:71611] [Bug #11721]'
    str = "\u{1f363}".taint
    assert_not_predicate(str, :frozen?)
    assert_equal str, str.to_sym.to_s
    assert_not_predicate(str, :frozen?, bug11721)
  end
end
