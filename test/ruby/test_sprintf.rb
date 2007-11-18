require 'test/unit'

class TestSprintf < Test::Unit::TestCase
  def test_positional
    assert_equal("     00001", sprintf("%*1$.*2$3$d", 10, 5, 1))
  end

  def test_binary
    assert_equal("0", sprintf("%b", 0))
    assert_equal("1", sprintf("%b", 1))
    assert_equal("10", sprintf("%b", 2))
    assert_equal("..1", sprintf("%b", -1))

    assert_equal("   0", sprintf("%4b", 0))
    assert_equal("   1", sprintf("%4b", 1))
    assert_equal("  10", sprintf("%4b", 2))
    assert_equal(" ..1", sprintf("%4b", -1))

    assert_equal("0000", sprintf("%04b", 0))
    assert_equal("0001", sprintf("%04b", 1))
    assert_equal("0010", sprintf("%04b", 2))
    assert_equal("1111", sprintf("%04b", -1))

    assert_equal("0000", sprintf("%.4b", 0))
    assert_equal("0001", sprintf("%.4b", 1))
    assert_equal("0010", sprintf("%.4b", 2))
    assert_equal("1111", sprintf("%.4b", -1))

    assert_equal("  0000", sprintf("%6.4b", 0))
    assert_equal("  0001", sprintf("%6.4b", 1))
    assert_equal("  0010", sprintf("%6.4b", 2))
    assert_equal("  1111", sprintf("%6.4b", -1))

    assert_equal(" 0b0", sprintf("%#4b", 0))
    assert_equal(" 0b1", sprintf("%#4b", 1))
    assert_equal("0b10", sprintf("%#4b", 2))
    assert_equal("0b..1", sprintf("%#4b", -1))

    assert_equal("0b00", sprintf("%#04b", 0))
    assert_equal("0b01", sprintf("%#04b", 1))
    assert_equal("0b10", sprintf("%#04b", 2))
    assert_equal("0b11", sprintf("%#04b", -1))

    assert_equal("0b0000", sprintf("%#.4b", 0))
    assert_equal("0b0001", sprintf("%#.4b", 1))
    assert_equal("0b0010", sprintf("%#.4b", 2))
    assert_equal("0b1111", sprintf("%#.4b", -1))

    assert_equal("0b0000", sprintf("%#6.4b", 0))
    assert_equal("0b0001", sprintf("%#6.4b", 1))
    assert_equal("0b0010", sprintf("%#6.4b", 2))
    assert_equal("0b1111", sprintf("%#6.4b", -1))

    assert_equal("+0", sprintf("%+b", 0))
    assert_equal("+1", sprintf("%+b", 1))
    assert_equal("+10", sprintf("%+b", 2))
    assert_equal("-1", sprintf("%+b", -1))

    assert_equal("  +0", sprintf("%+4b", 0))
    assert_equal("  +1", sprintf("%+4b", 1))
    assert_equal(" +10", sprintf("%+4b", 2))
    assert_equal("  -1", sprintf("%+4b", -1))

    assert_equal("+000", sprintf("%+04b", 0))
    assert_equal("+001", sprintf("%+04b", 1))
    assert_equal("+010", sprintf("%+04b", 2))
    assert_equal("-001", sprintf("%+04b", -1))

    assert_equal("+0000", sprintf("%+.4b", 0))
    assert_equal("+0001", sprintf("%+.4b", 1))
    assert_equal("+0010", sprintf("%+.4b", 2))
    assert_equal("-0001", sprintf("%+.4b", -1))

    assert_equal(" +0000", sprintf("%+6.4b", 0))
    assert_equal(" +0001", sprintf("%+6.4b", 1))
    assert_equal(" +0010", sprintf("%+6.4b", 2))
    assert_equal(" -0001", sprintf("%+6.4b", -1))
  end

  def test_nan
    nan = 0.0 / 0.0
    assert_equal("NaN", sprintf("%f", nan))
    assert_equal("NaN", sprintf("%-f", nan))
    assert_equal("+NaN", sprintf("%+f", nan))

    assert_equal("     NaN", sprintf("%8f", nan))
    assert_equal("NaN     ", sprintf("%-8f", nan))
    assert_equal("    +NaN", sprintf("%+8f", nan))

    assert_equal("00000NaN", sprintf("%08f", nan))
    assert_equal("NaN     ", sprintf("%-08f", nan))
    assert_equal("+0000NaN", sprintf("%+08f", nan))

    assert_equal("     NaN", sprintf("% 8f", nan))
    assert_equal(" NaN    ", sprintf("%- 8f", nan))
    assert_equal("    +NaN", sprintf("%+ 8f", nan))

    assert_equal(" 0000NaN", sprintf("% 08f", nan))
    assert_equal(" NaN    ", sprintf("%- 08f", nan))
    assert_equal("+0000NaN", sprintf("%+ 08f", nan))
  end

  def test_inf
    inf = 1.0 / 0.0
    assert_equal("Inf", sprintf("%f", inf))
    assert_equal("Inf", sprintf("%-f", inf))
    assert_equal("+Inf", sprintf("%+f", inf))

    assert_equal("     Inf", sprintf("%8f", inf))
    assert_equal("Inf     ", sprintf("%-8f", inf))
    assert_equal("    +Inf", sprintf("%+8f", inf))

    assert_equal("00000Inf", sprintf("%08f", inf))
    assert_equal("Inf     ", sprintf("%-08f", inf))
    assert_equal("+0000Inf", sprintf("%+08f", inf))

    assert_equal("     Inf", sprintf("% 8f", inf))
    assert_equal(" Inf    ", sprintf("%- 8f", inf))
    assert_equal("    +Inf", sprintf("%+ 8f", inf))

    assert_equal(" 0000Inf", sprintf("% 08f", inf))
    assert_equal(" Inf    ", sprintf("%- 08f", inf))
    assert_equal("+0000Inf", sprintf("%+ 08f", inf))

    assert_equal("-Inf", sprintf("%f", -inf))
    assert_equal("-Inf", sprintf("%-f", -inf))
    assert_equal("-Inf", sprintf("%+f", -inf))

    assert_equal("    -Inf", sprintf("%8f", -inf))
    assert_equal("-Inf    ", sprintf("%-8f", -inf))
    assert_equal("    -Inf", sprintf("%+8f", -inf))

    assert_equal("-0000Inf", sprintf("%08f", -inf))
    assert_equal("-Inf    ", sprintf("%-08f", -inf))
    assert_equal("-0000Inf", sprintf("%+08f", -inf))

    assert_equal("    -Inf", sprintf("% 8f", -inf))
    assert_equal("-Inf    ", sprintf("%- 8f", -inf))
    assert_equal("    -Inf", sprintf("%+ 8f", -inf))

    assert_equal("-0000Inf", sprintf("% 08f", -inf))
    assert_equal("-Inf    ", sprintf("%- 08f", -inf))
    assert_equal("-0000Inf", sprintf("%+ 08f", -inf))
  end

  def test_invalid
    # Star precision before star width:
    assert_raise(ArgumentError, "[ruby-core:11569]") {sprintf("%.**d", 5, 10, 1)}

    # Precision before flags and width:
    assert_raise(ArgumentError, "[ruby-core:11569]") {sprintf("%.5+05d", 5)}
    assert_raise(ArgumentError, "[ruby-core:11569]") {sprintf("%.5 5d", 5)}

    # Overriding a star width with a numeric one:
    assert_raise(ArgumentError, "[ruby-core:11569]") {sprintf("%*1s", 5, 1)}

    # Width before flags:
    assert_raise(ArgumentError, "[ruby-core:11569]") {sprintf("%5+0d", 1)}
    assert_raise(ArgumentError, "[ruby-core:11569]") {sprintf("%5 0d", 1)}

    # Specifying width multiple times:
    assert_raise(ArgumentError, "[ruby-core:11569]") {sprintf("%50+30+20+10+5d", 5)}
    assert_raise(ArgumentError, "[ruby-core:11569]") {sprintf("%50 30 20 10 5d", 5)}

    # Specifying the precision multiple times with negative star arguments:
    assert_raise(ArgumentError, "[ruby-core:11570]") {sprintf("%.*.*.*.*f", -1, -1, -1, 5, 1)}

    # Null bytes after percent signs are removed:
    assert_equal("%\0x hello", sprintf("%\0x hello"), "[ruby-core:11571]")

    assert_raise(ArgumentError, "[ruby-core:11573]") {sprintf("%.25555555555555555555555555555555555555s", "hello")}
  end
end
