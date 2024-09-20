# frozen_string_literal: true

require 'pp'
require 'delegate'
require 'test/unit'
require 'ruby2_keywords'

module PPTestModule

class PPTest < Test::Unit::TestCase
  def test_list0123_12
    assert_equal("[0, 1, 2, 3]\n", PP.pp([0,1,2,3], ''.dup, 12))
  end

  def test_list0123_11
    assert_equal("[0,\n 1,\n 2,\n 3]\n", PP.pp([0,1,2,3], ''.dup, 11))
  end

  OverriddenStruct = Struct.new("OverriddenStruct", :members, :class)
  def test_struct_override_members # [ruby-core:7865]
    a = OverriddenStruct.new(1,2)
    assert_equal("#<struct Struct::OverriddenStruct members=1, class=2>\n", PP.pp(a, ''.dup))
  end

  def test_redefined_method
    o = "".dup
    def o.method
    end
    assert_equal(%(""\n), PP.pp(o, "".dup))
  end

  def test_range
    assert_equal("0..1\n", PP.pp(0..1, "".dup))
    assert_equal("0...1\n", PP.pp(0...1, "".dup))
    assert_equal("0...\n", PP.pp(0..., "".dup))
    assert_equal("...1\n", PP.pp(...1, "".dup))
  end
end

class HasInspect
  def initialize(a)
    @a = a
  end

  def inspect
    return "<inspect:#{@a.inspect}>"
  end
end

class HasPrettyPrint
  def initialize(a)
    @a = a
  end

  def pretty_print(q)
    q.text "<pretty_print:"
    q.pp @a
    q.text ">"
  end
end

class HasBoth
  def initialize(a)
    @a = a
  end

  def inspect
    return "<inspect:#{@a.inspect}>"
  end

  def pretty_print(q)
    q.text "<pretty_print:"
    q.pp @a
    q.text ">"
  end
end

class PrettyPrintInspect < HasPrettyPrint
  alias inspect pretty_print_inspect
end

class PrettyPrintInspectWithoutPrettyPrint
  alias inspect pretty_print_inspect
end

class PPInspectTest < Test::Unit::TestCase
  def test_hasinspect
    a = HasInspect.new(1)
    assert_equal("<inspect:1>\n", PP.pp(a, ''.dup))
  end

  def test_hasprettyprint
    a = HasPrettyPrint.new(1)
    assert_equal("<pretty_print:1>\n", PP.pp(a, ''.dup))
  end

  def test_hasboth
    a = HasBoth.new(1)
    assert_equal("<pretty_print:1>\n", PP.pp(a, ''.dup))
  end

  def test_pretty_print_inspect
    a = PrettyPrintInspect.new(1)
    assert_equal("<pretty_print:1>", a.inspect)
    a = PrettyPrintInspectWithoutPrettyPrint.new
    assert_raise(RuntimeError) { a.inspect }
  end

  def test_proc
    a = proc {1}
    assert_equal("#{a.inspect}\n", PP.pp(a, ''.dup))
  end

  def test_to_s_with_iv
    a = Object.new
    def a.to_s() "aaa" end
    a.instance_eval { @a = nil }
    result = PP.pp(a, ''.dup)
    assert_equal("#{a.inspect}\n", result)
  end

  def test_to_s_without_iv
    a = Object.new
    def a.to_s() "aaa" end
    result = PP.pp(a, ''.dup)
    assert_equal("#{a.inspect}\n", result)
  end
end

class PPCycleTest < Test::Unit::TestCase
  def test_array
    a = []
    a << a
    assert_equal("[[...]]\n", PP.pp(a, ''.dup))
    assert_equal("#{a.inspect}\n", PP.pp(a, ''.dup))
  end

  def test_hash
    a = {}
    a[0] = a
    assert_equal("{0=>{...}}\n", PP.pp(a, ''.dup))
    assert_equal("#{a.inspect}\n", PP.pp(a, ''.dup))
  end

  S = Struct.new("S", :a, :b)
  def test_struct
    a = S.new(1,2)
    a.b = a
    assert_equal("#<struct Struct::S a=1, b=#<struct Struct::S:...>>\n", PP.pp(a, ''.dup))
    assert_equal("#{a.inspect}\n", PP.pp(a, ''.dup)) unless RUBY_ENGINE == "truffleruby"
  end

  if defined?(Data.define)
    D = Data.define(:aaa, :bbb)
    def test_data
      a = D.new("aaa", "bbb")
      assert_equal("#<data PPTestModule::PPCycleTest::D\n aaa=\"aaa\",\n bbb=\"bbb\">\n", PP.pp(a, ''.dup, 20))
      assert_equal("#{a.inspect}\n", PP.pp(a, ''.dup))

      b = Data.define(:a).new(42)
      assert_equal("#{b.inspect}\n", PP.pp(b, ''.dup))
    end
  end

  def test_object
    a = Object.new
    a.instance_eval {@a = a}
    assert_equal(a.inspect + "\n", PP.pp(a, ''.dup))
  end

  def test_anonymous
    a = Class.new.new
    assert_equal(a.inspect + "\n", PP.pp(a, ''.dup))
  end

  def test_withinspect
    omit if RUBY_ENGINE == "jruby" or RUBY_ENGINE == "truffleruby"
    a = []
    a << HasInspect.new(a)
    assert_equal("[<inspect:[...]>]\n", PP.pp(a, ''.dup))
    assert_equal("#{a.inspect}\n", PP.pp(a, ''.dup))
  end

  def test_share_nil
    begin
      PP.sharing_detection = true
      a = [nil, nil]
      assert_equal("[nil, nil]\n", PP.pp(a, ''.dup))
    ensure
      PP.sharing_detection = false
    end
  end
end

class PPSingleLineTest < Test::Unit::TestCase
  def test_hash
    assert_equal("{1=>1}", PP.singleline_pp({ 1 => 1}, ''.dup)) # [ruby-core:02699]
    assert_equal("[1#{', 1'*99}]", PP.singleline_pp([1]*100, ''.dup))
  end

  def test_hash_in_array
    omit if RUBY_ENGINE == "jruby"
    assert_equal("[{}]", PP.singleline_pp([->(*a){a.last.clear}.ruby2_keywords.call(a: 1)], ''.dup))
    assert_equal("[{}]", PP.singleline_pp([Hash.ruby2_keywords_hash({})], ''.dup))
  end
end

class PPDelegateTest < Test::Unit::TestCase
  class A < DelegateClass(Array); end

  def test_delegate
    assert_equal("[]\n", A.new([]).pretty_inspect, "[ruby-core:25804]")
  end

  def test_delegate_cycle
    a = HasPrettyPrint.new nil

    a.instance_eval {@a = a}
    cycle_pretty_inspect = a.pretty_inspect

    a.instance_eval {@a = SimpleDelegator.new(a)}
    delegator_cycle_pretty_inspect = a.pretty_inspect

    assert_equal(cycle_pretty_inspect, delegator_cycle_pretty_inspect)
  end
end

class PPFileStatTest < Test::Unit::TestCase
  def test_nothing_raised
    assert_nothing_raised do
      File.stat(__FILE__).pretty_inspect
    end
  end
end

if defined?(RubyVM)
  class PPAbstractSyntaxTree < Test::Unit::TestCase
    AST = RubyVM::AbstractSyntaxTree
    def test_lasgn_literal
      ast = AST.parse("_=1")
      integer = RUBY_VERSION >= "3.4." ? "INTEGER" : "LIT"
      expected = "(SCOPE@1:0-1:3 tbl: [:_] args: nil body: (LASGN@1:0-1:3 :_ (#{integer}@1:2-1:3 1)))"
      assert_equal(expected, PP.singleline_pp(ast, ''.dup), ast)
    end
  end
end

class PPInheritedTest < Test::Unit::TestCase
  class PPSymbolHash < PP
    def pp_hash_pair(k, v)
      case k
      when Symbol
        text k.inspect.delete_prefix(":")
        text ":"
        group(1) {
          breakable
          pp v
        }
      else
        super
      end
    end
  end

  def test_hash_override
    obj = {k: 1, "": :null, "0": :zero, 100 => :ten}
    assert_equal <<~EXPECT, PPSymbolHash.pp(obj, "".dup)
    {k: 1, "": :null, "0": :zero, 100=>:ten}
    EXPECT
  end
end

end
