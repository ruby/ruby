require 'test/unit'

class TestSprintf < Test::Unit::TestCase
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
end
