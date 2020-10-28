# frozen_string_literal: false
require 'test/unit'
require "-test-/printf"
require_relative '../ruby/allpairs'

class Test_SPrintf < Test::Unit::TestCase
  def to_s
    "#{self.class}:#{object_id}"
  end

  def inspect
    "<#{self.class}:#{object_id}>"
  end

  def test_to_str
    assert_equal("<#{self.class}:#{object_id}>", Bug::Printf.s(self))
  end

  def test_inspect
    assert_equal("{<#{self.class}:#{object_id}>}", Bug::Printf.v(self))
  end

  def test_quote
    assert_equal('["\n"]', Bug::Printf.q("\n"))
    assert_equal('[aaa]', Bug::Printf.q('aaa'))
    assert_equal('[a a]', Bug::Printf.q('a a'))
    assert_equal('[]', Bug::Printf.q(''))
    assert_equal('[""]', Bug::Printf.q(:''))
  end

  def test_encoding
    def self.to_s
      "\u{3042 3044 3046 3048 304a}"
    end
    assert_equal("<\u{3042 3044 3046 3048 304a}>", Bug::Printf.s(self))
  end

  VS = [
    #-0x1000000000000000000000000000000000000000000000002,
    #-0x1000000000000000000000000000000000000000000000001,
    #-0x1000000000000000000000000000000000000000000000000,
    #-0xffffffffffffffffffffffffffffffffffffffffffffffff,
    #-0x1000000000000000000000002,
    #-0x1000000000000000000000001,
    #-0x1000000000000000000000000,
    #-0xffffffffffffffffffffffff,
    -0x10000000000000002,
    -0x10000000000000001,
    -0x10000000000000000,
    -0xffffffffffffffff,
    -0x4000000000000002,
    -0x4000000000000001,
    -0x4000000000000000,
    -0x3fffffffffffffff,
    -0x100000002,
    -0x100000001,
    -0x100000000,
    -0xffffffff,
    #-0xc717a08d, # 0xc717a08d * 0x524b2245 = 0x4000000000000001
    -0x80000002,
    -0x80000001,
    -0x80000000,
    -0x7fffffff,
    #-0x524b2245,
    -0x40000002,
    -0x40000001,
    -0x40000000,
    -0x3fffffff,
    #-0x10002,
    #-0x10001,
    #-0x10000,
    #-0xffff,
    #-0x8101, # 0x8101 * 0x7f01 = 0x40000001
    #-0x8002,
    #-0x8001,
    #-0x8000,
    #-0x7fff,
    #-0x7f01,
    #-65,
    #-64,
    #-63,
    #-62,
    #-33,
    #-32,
    #-31,
    #-30,
    -3,
    -2,
    -1,
    0,
    1,
    2,
    3,
    #30,
    #31,
    #32,
    #33,
    #62,
    #63,
    #64,
    #65,
    #0x7f01,
    #0x7ffe,
    #0x7fff,
    #0x8000,
    #0x8001,
    #0x8101,
    #0xfffe,
    #0xffff,
    #0x10000,
    #0x10001,
    0x3ffffffe,
    0x3fffffff,
    0x40000000,
    0x40000001,
    #0x524b2245,
    0x7ffffffe,
    0x7fffffff,
    0x80000000,
    0x80000001,
    #0xc717a08d,
    0xfffffffe,
    0xffffffff,
    0x100000000,
    0x100000001,
    0x3ffffffffffffffe,
    0x3fffffffffffffff,
    0x4000000000000000,
    0x4000000000000001,
    0xfffffffffffffffe,
    0xffffffffffffffff,
    0x10000000000000000,
    0x10000000000000001,
    #0xffffffffffffffffffffffff,
    #0x1000000000000000000000000,
    #0x1000000000000000000000001,
    #0xffffffffffffffffffffffffffffffffffffffffffffffff,
    #0x1000000000000000000000000000000000000000000000000,
    #0x1000000000000000000000000000000000000000000000001
  ]
  VS.reverse!

  FLAGS = [[nil, ' '], [nil, '#'], [nil, '+'], [nil, '-'], [nil, '0']]

  def self.assertions_format_integer(format, type, **opts)
    proc {
      VS.each {|v|
        begin
          r = Bug::Printf.(type, v, **opts)
        rescue RangeError
        else
          e = sprintf format, v
          assert_equal([e, format], r, "rb_sprintf(#{format.dump}, #{v})")
        end
      }
    }
  end

  AllPairs.each(%w[d],
                # octal and hexadecimal deal with negative values differently
                [nil, 0, 5, 20],
                [nil, true, 0], # 8, 20
                *FLAGS) {
    |type, width, prec, sp, hs, pl, mi, zr|
    precision = ".#{prec unless prec == true}" if prec
    format = "%#{sp}#{hs}#{pl}#{mi}#{zr}#{width}#{precision}#{type}"
    define_method("test_format_integer(#{format})",
                  assertions_format_integer(format, type,
                                            space: sp, hash: hs,
                                            plus: pl, minus: mi,
                                            zero: zr, width: width,
                                            prec: prec))
  }

  def test_string_prec
    assert_equal("a", Bug::Printf.("s", "a", prec: 3)[0])
    assert_equal("  a", Bug::Printf.("s", "a", width: 3, prec: 3)[0])
    assert_equal("a  ", Bug::Printf.("s", "a", minus: true, width: 3, prec: 3)[0])
  end

  def test_snprintf_count
    assert_equal(3, Bug::Printf.sncount("foo"))
  end
end
