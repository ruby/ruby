require 'test/unit'

class TestSymbol < Test::Unit::TestCase
  # [ruby-core:3573]

  def assert_eval_inspected(sym)
    n = sym.inspect
    assert_nothing_raised(SyntaxError) {assert_equal(sym, eval(n))}
  end

  def test_inspect_invalid
    # 2) Symbol#inspect sometimes returns invalid symbol representations:
    assert_eval_inspected(:"!")
    assert_eval_inspected(:"=")
    assert_eval_inspected(:"0")
    assert_eval_inspected(:"$1")
    assert_eval_inspected(:"@1")
    assert_eval_inspected(:"@@1")
    assert_eval_inspected(:"@")
    assert_eval_inspected(:"@@")
  end

  def assert_inspect_evaled(n)
    assert_nothing_raised(SyntaxError) {assert_equal(n, eval(n).inspect)}
  end

  def test_inspect_suboptimal
    # 3) Symbol#inspect sometimes returns suboptimal symbol representations:
    assert_inspect_evaled(':foo')
    assert_inspect_evaled(':foo!')
    assert_inspect_evaled(':bar?')
    assert_inspect_evaled(':<<')
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
    sym = "$-".intern
    assert_nothing_raised(SyntaxError) {assert_equal(sym, eval(':$-'))}
    assert_nothing_raised(SyntaxError) {assert_equal(sym, eval(":$-\n"))}
    assert_nothing_raised(SyntaxError) {assert_equal(sym, eval(":$- "))}
    assert_nothing_raised(SyntaxError) {assert_equal(sym, eval(":$-#"))}
    assert_raise(SyntaxError) {eval ':$-('}
  end

  def test_inspect_number
    # 5) Inconsistency between :$0 and :$1? The first one is valid, but the
    # latter isn't.
    assert_inspect_evaled(':$0')
    assert_inspect_evaled(':$1')
  end

  def test_inspect
    valid = %w{$a @a @@a < << <= <=> > >> >= =~ == === * ** + +@ - -@
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

  def test_no_inadvertent_symbol_creation
    feature5072 = '[ruby-core:38367]'
    c = Class.new
    s = "gadzooks"
    {:respond_to? => "#{s}1", :method_defined? => "#{s}2",
     :public_method_defined? => "#{s}3", :private_method_defined? => "#{s}4",
     :protected_method_defined? => "#{s}5", :const_defined? => "A#{s}",
     :instance_variable_defined? => "@#{s}", :class_variable_defined? => "@@#{s}"
    }.each do |meth, str|
      msg = "#{meth}(#{str}) #{feature5072}"
      assert !c.send(meth, str), msg
      assert !Symbol.all_symbols.any? {|sym| sym.to_s == str}, msg
    end
  end

  def test_no_inadvertent_symbol_creation2
    feature5079 = '[ruby-core:38404]'
    c = Class.new
    s = "gadzoooks"
    {:instance_variable_get => ["@#{s}1", nil],
     :class_variable_get => ["@@#{s}1", NameError],
     :remove_instance_variable => ["@#{s}2", NameError],
     :remove_class_variable => ["@@#{s}2", NameError],
     :remove_const => ["A#{s}", NameError],
     :method => ["#{s}1", NameError],
     :public_method => ["#{s}2", NameError],
     :instance_method => ["#{s}3", NameError],
     :public_instance_method => ["#{s}4", NameError],
    }.each do |meth, arr|
      str, ret = arr
      msg = "#{meth}(#{str}) #{feature5079}"
      if ret.is_a?(Class) && (ret < Exception)
        assert_raises(ret){c.send(meth, str)}
      else
        assert(c.send(meth, str) == ret, msg)
      end
      assert !Symbol.all_symbols.any? {|sym| sym.to_s == str}, msg
    end
  end

  def test_no_inadvertent_symbol_creation3
    feature5089 = '[ruby-core:38447]'
    c = Class.new do
      def self.alias_method(str)
        super(:puts, str)
      end
    end
    s = "gadzoooks"
    {:alias_method => ["#{s}1", NameError],
     :autoload? => ["#{s}2", nil],
     :const_get => ["A#{s}3", NameError],
     :private_class_method => ["#{s}4", NameError],
     :private_constant => ["#{s}5", NameError],
     :private => ["#{s}6", NameError],
     :protected => ["#{s}7", NameError],
     :public => ["#{s}8", NameError],
     :public_class_method => ["#{s}9", NameError],
     :public_constant => ["#{s}10", NameError],
     :remove_method => ["#{s}11", NameError],
     :undef_method => ["#{s}12", NameError],
     :untrace_var => ["#{s}13", NameError],
    }.each do |meth, arr|
      str, ret = arr
      msg = "#{meth}(#{str}) #{feature5089}"
      if ret.is_a?(Class) && (ret < Exception)
        assert_raises(ret){c.send(meth, str)}
      else
        assert(c.send(meth, str) == ret, msg)
      end
      assert !Symbol.all_symbols.any? {|sym| sym.to_s == str}, msg
    end
  end
end
