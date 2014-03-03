require 'test/unit'
require_relative 'envutil'

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

  def test_frozen_symbol
    assert_equal(true, :foo.frozen?)
    assert_equal(true, :each.frozen?)
    assert_equal(true, :+.frozen?)
    assert_equal(true, "foo#{Time.now.to_i}".to_sym.frozen?)
    assert_equal(true, :foo.to_sym.frozen?)
  end

  def test_sym_find
    assert_separately(%w[--disable=gems], <<-"end;")
      assert_equal :intern, Symbol.find("intern")
      assert_raise(TypeError){ Symbol.find(true) }

      str = "__noexistent__"
      assert_equal nil, Symbol.find(str)
      assert_equal nil, Symbol.find(str)
      sym = str.intern
      assert_equal str, sym.to_s
      assert_equal sym, Symbol.find(str)
    end;
  end
end
