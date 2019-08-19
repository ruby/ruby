# frozen_string_literal: false
require 'test/unit'

class TestInteger < Test::Unit::TestCase
  BDSIZE = 0x4000000000000000.coerce(0)[0].size
  def self.bdsize(x)
    ((x + 1) / 8 + BDSIZE) / BDSIZE * BDSIZE
  end
  def bdsize(x)
    self.class.bdsize(x)
  end

  def test_aref
    # assert_equal(1, (1 << 0x40000000)[0x40000000], "[ruby-dev:31271]")
    # assert_equal(0, (-1 << 0x40000001)[0x40000000], "[ruby-dev:31271]")
    big_zero = 0x40000000.coerce(0)[0]
    assert_equal(0, (-0x40000002)[big_zero], "[ruby-dev:31271]")
    assert_equal(1, 0x400000001[big_zero], "[ruby-dev:31271]")
  end

  def test_pow
    assert_not_equal(0, begin
                          0**-1
                        rescue
                          nil
                        end, "[ruby-dev:32084] [ruby-dev:34547]")

    x = EnvUtil.suppress_warning {2 ** -0x4000000000000000}
    assert_in_delta(0.0, (x / 2), Float::EPSILON)

    <<~EXPRS.each_line.with_index(__LINE__+1) do |expr, line|
      crash01: 111r+11**-11111161111111
      crash02: 1118111111111**-1111111111111111**1+1==11111
      crash03: -1111111**-1111*11 - -1111111** -111111111
      crash04: 1118111111111** -1111111111111111**1+11111111111**1 ===111
      crash05: 11** -111155555555555555  -55   !=5-555
      crash07: 1 + 111111111**-1111811111
      crash08: 18111111111**-1111111111111111**1 + 1111111111**-1111**1
      crash10: -7 - -1111111** -1111**11
      crash12: 1118111111111** -1111111111111111**1 + 1111 - -1111111** -1111*111111111119
      crash13: 1.0i - -1111111** -111111111
      crash14: 11111**111111111**111111 * -11111111111111111111**-111111111111
      crash15: ~1**1111 + -~1**~1**111
      crash17: 11** -1111111**1111 /11i
      crash18: 5555i**-5155 - -9111111**-1111**11
      crash19: 111111*-11111111111111111111**-1111111111111111
      crash20: 1111**111-11**-11111**11
      crash21: 11**-10111111119-1i -1r
    EXPRS
      name, expr = expr.split(':', 2)
      assert_ruby_status(%w"-W0", expr, name)
    end
  end

  def test_lshift
    assert_equal(0, 1 << -0x40000000)
    assert_equal(0, 1 << -0x40000001)
    assert_equal(0, 1 << -0x80000000)
    assert_equal(0, 1 << -0x80000001)
    # assert_equal(bdsize(0x80000000), (1 << 0x80000000).size)
  end

  def test_rshift
    # assert_equal(bdsize(0x40000001), (1 >> -0x40000001).size)
    assert_predicate((1 >> 0x80000000), :zero?)
    assert_predicate((1 >> 0xffffffff), :zero?)
    assert_predicate((1 >> 0x100000000), :zero?)
    # assert_equal((1 << 0x40000000), (1 >> -0x40000000))
    # assert_equal((1 << 0x40000001), (1 >> -0x40000001))
  end

  def test_Integer
    assert_raise(ArgumentError) {Integer("0x-1")}
    assert_raise(ArgumentError) {Integer("-0x-1")}
    assert_raise(ArgumentError) {Integer("0x     123")}
    assert_raise(ArgumentError) {Integer("0x      123")}
    assert_raise(ArgumentError) {Integer("0x0x5")}
    assert_raise(ArgumentError) {Integer("0x0x000000005")}
    assert_nothing_raised(ArgumentError) {
      assert_equal(1540841, "0x0x5".to_i(36))
    }
    assert_raise(ArgumentError) { Integer("--0") }
    assert_raise(ArgumentError) { Integer("-+0") }
    assert_raise(ArgumentError) { Integer("++1") }
    assert_raise(ArgumentError) { Integer("") }
    assert_raise(ArgumentError) { Integer("10  x") }
    assert_raise(ArgumentError) { Integer("1__2") }
    assert_raise(ArgumentError) { Integer("1z") }
    assert_raise(ArgumentError) { Integer("46116860184273__87904") }
    assert_raise(ArgumentError) { Integer("4611686018427387904_") }
    assert_raise(ArgumentError) { Integer("4611686018427387904  :") }
    assert_equal(0x4000000000000000, Integer("46_11_686_0184273_87904"))
    assert_raise(ArgumentError) { Integer("\0") }
    assert_nothing_raised(ArgumentError, "[ruby-core:13873]") {
      assert_equal(0, Integer("0 "))
    }
    assert_nothing_raised(ArgumentError, "[ruby-core:14139]") {
      assert_equal(0377, Integer("0_3_7_7"))
    }
    assert_raise(ArgumentError, "[ruby-core:14139]") {Integer("0__3_7_7")}
    assert_equal(1234, Integer(1234))
    assert_equal(1, Integer(1.234))

    # base argument
    assert_equal(1234, Integer("1234", 10))
    assert_equal(668, Integer("1234", 8))
    assert_equal(4660, Integer("1234", 16))
    assert_equal(49360, Integer("1234", 36))
    # decimal, not octal
    assert_equal(1234, Integer("01234", 10))
    assert_raise(ArgumentError) { Integer("0x123", 10) }
    assert_raise(ArgumentError) { Integer(1234, 10) }
    assert_raise(ArgumentError) { Integer(12.34, 10) }
    assert_raise(ArgumentError) { Integer(Object.new, 1) }

    assert_raise(ArgumentError) { Integer(1, 1, 1) }

    assert_equal(2 ** 50, Integer(2.0 ** 50))
    assert_raise(TypeError) { Integer(nil) }

    bug14552 = '[ruby-core:85813]'
    obj = Object.new
    def obj.to_int; "str"; end
    assert_raise(TypeError, bug14552) { Integer(obj) }
    def obj.to_i; 42; end
    assert_equal(42, Integer(obj), bug14552)

    obj = Object.new
    def obj.to_i; "str"; end
    assert_raise(TypeError) { Integer(obj) }

    bug6192 = '[ruby-core:43566]'
    assert_raise(Encoding::CompatibilityError, bug6192) {Integer("0".encode("utf-16be"))}
    assert_raise(Encoding::CompatibilityError, bug6192) {Integer("0".encode("utf-16le"))}
    assert_raise(Encoding::CompatibilityError, bug6192) {Integer("0".encode("utf-32be"))}
    assert_raise(Encoding::CompatibilityError, bug6192) {Integer("0".encode("utf-32le"))}
    assert_raise(Encoding::CompatibilityError, bug6192) {Integer("0".encode("iso-2022-jp"))}

    assert_raise_with_message(ArgumentError, /\u{1f4a1}/) {Integer("\u{1f4a1}")}

    obj = Struct.new(:s).new(%w[42 not-an-integer])
    def obj.to_str; s.shift; end
    assert_equal(42, Integer(obj, 10))

    assert_separately([], "#{<<-"begin;"}\n#{<<-"end;"}")
    begin;
      class Float
        undef to_int
        def to_int; raise "conversion failed"; end
      end
      assert_equal (1 << 100), Integer((1 << 100).to_f)
      assert_equal 1, Integer(1.0)
    end;
  end

  def test_Integer_with_exception_keyword
    assert_nothing_raised(ArgumentError) {
      assert_equal(nil, Integer("1z", exception: false))
    }
    assert_nothing_raised(ArgumentError) {
      assert_equal(nil, Integer(Object.new, exception: false))
    }
    assert_nothing_raised(ArgumentError) {
      o = Object.new
      def o.to_i; 42.5; end
      assert_equal(nil, Integer(o, exception: false))
    }
    assert_nothing_raised(ArgumentError) {
      o = Object.new
      def o.to_i; raise; end
      assert_equal(nil, Integer(o, exception: false))
    }
    assert_nothing_raised(ArgumentError) {
      o = Object.new
      def o.to_int; raise; end
      assert_equal(nil, Integer(o, exception: false))
    }
    assert_nothing_raised(FloatDomainError) {
      assert_equal(nil, Integer(Float::INFINITY, exception: false))
    }
    assert_nothing_raised(FloatDomainError) {
      assert_equal(nil, Integer(-Float::INFINITY, exception: false))
    }
    assert_nothing_raised(FloatDomainError) {
      assert_equal(nil, Integer(Float::NAN, exception: false))
    }

    assert_raise(ArgumentError) {
      Integer("1z", exception: true)
    }
    assert_raise(TypeError) {
      Integer(nil, exception: true)
    }
    assert_nothing_raised(TypeError) {
      assert_equal(nil, Integer(nil, exception: false))
    }

    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      class Integer;def method_missing(*);"";end;end
      assert_equal(0, Integer("0", 2))
    end;
  end

  def test_int_p
    assert_not_predicate(1.0, :integer?)
    assert_predicate(1, :integer?)
  end

  def test_succ
    assert_equal(2, 1.send(:succ))
  end

  def test_chr
    assert_equal("a", "a".ord.chr)
    assert_raise(RangeError) { (-1).chr }
    assert_raise(RangeError) { 0x100.chr }
  end

  def test_upto
    a = []
    1.upto(3) {|x| a << x }
    assert_equal([1, 2, 3], a)

    a = []
    1.upto(0) {|x| a << x }
    assert_equal([], a)

    y = 2**30 - 1
    a = []
    y.upto(y+2) {|x| a << x }
    assert_equal([y, y+1, y+2], a)
  end

  def test_downto
    a = []
    -1.downto(-3) {|x| a << x }
    assert_equal([-1, -2, -3], a)

    a = []
    1.downto(2) {|x| a << x }
    assert_equal([], a)

    y = -(2**30)
    a = []
    y.downto(y-2) {|x| a << x }
    assert_equal([y, y-1, y-2], a)
  end

  def test_times
    (2**32).times do |i|
      break if i == 2
    end
  end

  def assert_int_equal(expected, result, mesg = nil)
    assert_kind_of(Integer, result, mesg)
    assert_equal(expected, result, mesg)
  end

  def assert_float_equal(expected, result, mesg = nil)
    assert_kind_of(Float, result, mesg)
    assert_equal(expected, result, mesg)
  end

  def test_round
    assert_int_equal(11111, 11111.round)
    assert_int_equal(11111, 11111.round(0))

    assert_int_equal(11111, 11111.round(1))
    assert_int_equal(11111, 11111.round(2))

    assert_int_equal(11110, 11111.round(-1))
    assert_int_equal(11100, 11111.round(-2))
    assert_int_equal(+200, +249.round(-2))
    assert_int_equal(+300, +250.round(-2))
    assert_int_equal(-200, -249.round(-2))
    assert_int_equal(+200, +249.round(-2, half: :even))
    assert_int_equal(+200, +250.round(-2, half: :even))
    assert_int_equal(+300, +349.round(-2, half: :even))
    assert_int_equal(+400, +350.round(-2, half: :even))
    assert_int_equal(+200, +249.round(-2, half: :up))
    assert_int_equal(+300, +250.round(-2, half: :up))
    assert_int_equal(+300, +349.round(-2, half: :up))
    assert_int_equal(+400, +350.round(-2, half: :up))
    assert_int_equal(+200, +249.round(-2, half: :down))
    assert_int_equal(+200, +250.round(-2, half: :down))
    assert_int_equal(+300, +349.round(-2, half: :down))
    assert_int_equal(+300, +350.round(-2, half: :down))
    assert_int_equal(-300, -250.round(-2))
    assert_int_equal(-200, -249.round(-2, half: :even))
    assert_int_equal(-200, -250.round(-2, half: :even))
    assert_int_equal(-300, -349.round(-2, half: :even))
    assert_int_equal(-400, -350.round(-2, half: :even))
    assert_int_equal(-200, -249.round(-2, half: :up))
    assert_int_equal(-300, -250.round(-2, half: :up))
    assert_int_equal(-300, -349.round(-2, half: :up))
    assert_int_equal(-400, -350.round(-2, half: :up))
    assert_int_equal(-200, -249.round(-2, half: :down))
    assert_int_equal(-200, -250.round(-2, half: :down))
    assert_int_equal(-300, -349.round(-2, half: :down))
    assert_int_equal(-300, -350.round(-2, half: :down))
    assert_int_equal(+30 * 10**70, (+25 * 10**70).round(-71))
    assert_int_equal(-30 * 10**70, (-25 * 10**70).round(-71))
    assert_int_equal(+20 * 10**70, (+25 * 10**70 - 1).round(-71))
    assert_int_equal(-20 * 10**70, (-25 * 10**70 + 1).round(-71))
    assert_int_equal(+40 * 10**70, (+35 * 10**70).round(-71))
    assert_int_equal(-40 * 10**70, (-35 * 10**70).round(-71))
    assert_int_equal(+30 * 10**70, (+35 * 10**70 - 1).round(-71))
    assert_int_equal(-30 * 10**70, (-35 * 10**70 + 1).round(-71))
    assert_int_equal(+20 * 10**70, (+25 * 10**70).round(-71, half: :even))
    assert_int_equal(-20 * 10**70, (-25 * 10**70).round(-71, half: :even))
    assert_int_equal(+20 * 10**70, (+25 * 10**70 - 1).round(-71, half: :even))
    assert_int_equal(-20 * 10**70, (-25 * 10**70 + 1).round(-71, half: :even))
    assert_int_equal(+40 * 10**70, (+35 * 10**70).round(-71, half: :even))
    assert_int_equal(-40 * 10**70, (-35 * 10**70).round(-71, half: :even))
    assert_int_equal(+30 * 10**70, (+35 * 10**70 - 1).round(-71, half: :even))
    assert_int_equal(-30 * 10**70, (-35 * 10**70 + 1).round(-71, half: :even))
    assert_int_equal(+30 * 10**70, (+25 * 10**70).round(-71, half: :up))
    assert_int_equal(-30 * 10**70, (-25 * 10**70).round(-71, half: :up))
    assert_int_equal(+20 * 10**70, (+25 * 10**70 - 1).round(-71, half: :up))
    assert_int_equal(-20 * 10**70, (-25 * 10**70 + 1).round(-71, half: :up))
    assert_int_equal(+40 * 10**70, (+35 * 10**70).round(-71, half: :up))
    assert_int_equal(-40 * 10**70, (-35 * 10**70).round(-71, half: :up))
    assert_int_equal(+30 * 10**70, (+35 * 10**70 - 1).round(-71, half: :up))
    assert_int_equal(-30 * 10**70, (-35 * 10**70 + 1).round(-71, half: :up))
    assert_int_equal(+20 * 10**70, (+25 * 10**70).round(-71, half: :down))
    assert_int_equal(-20 * 10**70, (-25 * 10**70).round(-71, half: :down))
    assert_int_equal(+20 * 10**70, (+25 * 10**70 - 1).round(-71, half: :down))
    assert_int_equal(-20 * 10**70, (-25 * 10**70 + 1).round(-71, half: :down))
    assert_int_equal(+30 * 10**70, (+35 * 10**70).round(-71, half: :down))
    assert_int_equal(-30 * 10**70, (-35 * 10**70).round(-71, half: :down))
    assert_int_equal(+30 * 10**70, (+35 * 10**70 - 1).round(-71, half: :down))
    assert_int_equal(-30 * 10**70, (-35 * 10**70 + 1).round(-71, half: :down))

    assert_int_equal(1111_1111_1111_1111_1111_1111_1111_1110, 1111_1111_1111_1111_1111_1111_1111_1111.round(-1))
    assert_int_equal(-1111_1111_1111_1111_1111_1111_1111_1110, (-1111_1111_1111_1111_1111_1111_1111_1111).round(-1))

    assert_int_equal(1111_1111_1111_1111_1111_1111_1111_1111, 1111_1111_1111_1111_1111_1111_1111_1111.round(1))
    assert_int_equal(10**400, (10**400).round(1))
  end

  def test_floor
    assert_int_equal(11111, 11111.floor)
    assert_int_equal(11111, 11111.floor(0))

    assert_int_equal(11111, 11111.floor(1))
    assert_int_equal(11111, 11111.floor(2))

    assert_int_equal(11110, 11110.floor(-1))
    assert_int_equal(11110, 11119.floor(-1))
    assert_int_equal(11100, 11100.floor(-2))
    assert_int_equal(11100, 11199.floor(-2))
    assert_int_equal(0, 11111.floor(-5))
    assert_int_equal(+200, +299.floor(-2))
    assert_int_equal(+300, +300.floor(-2))
    assert_int_equal(-300, -299.floor(-2))
    assert_int_equal(-300, -300.floor(-2))
    assert_int_equal(+20 * 10**70, (+25 * 10**70).floor(-71))
    assert_int_equal(-30 * 10**70, (-25 * 10**70).floor(-71))
    assert_int_equal(+20 * 10**70, (+25 * 10**70 - 1).floor(-71))
    assert_int_equal(-30 * 10**70, (-25 * 10**70 + 1).floor(-71))

    assert_int_equal(1111_1111_1111_1111_1111_1111_1111_1110, 1111_1111_1111_1111_1111_1111_1111_1111.floor(-1))
    assert_int_equal(-1111_1111_1111_1111_1111_1111_1111_1120, (-1111_1111_1111_1111_1111_1111_1111_1111).floor(-1))

    assert_int_equal(1111_1111_1111_1111_1111_1111_1111_1111, 1111_1111_1111_1111_1111_1111_1111_1111.floor(1))
    assert_int_equal(10**400, (10**400).floor(1))
  end

  def test_ceil
    assert_int_equal(11111, 11111.ceil)
    assert_int_equal(11111, 11111.ceil(0))

    assert_int_equal(11111, 11111.ceil(1))
    assert_int_equal(11111, 11111.ceil(2))

    assert_int_equal(11110, 11110.ceil(-1))
    assert_int_equal(11120, 11119.ceil(-1))
    assert_int_equal(11200, 11101.ceil(-2))
    assert_int_equal(11200, 11200.ceil(-2))
    assert_int_equal(100000, 11111.ceil(-5))
    assert_int_equal(300, 299.ceil(-2))
    assert_int_equal(300, 300.ceil(-2))
    assert_int_equal(-200, -299.ceil(-2))
    assert_int_equal(-300, -300.ceil(-2))
    assert_int_equal(+30 * 10**70, (+25 * 10**70).ceil(-71))
    assert_int_equal(-20 * 10**70, (-25 * 10**70).ceil(-71))
    assert_int_equal(+30 * 10**70, (+25 * 10**70 - 1).ceil(-71))
    assert_int_equal(-20 * 10**70, (-25 * 10**70 + 1).ceil(-71))

    assert_int_equal(1111_1111_1111_1111_1111_1111_1111_1120, 1111_1111_1111_1111_1111_1111_1111_1111.ceil(-1))
    assert_int_equal(-1111_1111_1111_1111_1111_1111_1111_1110, (-1111_1111_1111_1111_1111_1111_1111_1111).ceil(-1))

    assert_int_equal(1111_1111_1111_1111_1111_1111_1111_1111, 1111_1111_1111_1111_1111_1111_1111_1111.ceil(1))
    assert_int_equal(10**400, (10**400).ceil(1))
  end

  def test_truncate
    assert_int_equal(11111, 11111.truncate)
    assert_int_equal(11111, 11111.truncate(0))

    assert_int_equal(11111, 11111.truncate(1))
    assert_int_equal(11111, 11111.truncate(2))

    assert_int_equal(11110, 11110.truncate(-1))
    assert_int_equal(11110, 11119.truncate(-1))
    assert_int_equal(11100, 11100.truncate(-2))
    assert_int_equal(11100, 11199.truncate(-2))
    assert_int_equal(0, 11111.truncate(-5))
    assert_int_equal(+200, +299.truncate(-2))
    assert_int_equal(+300, +300.truncate(-2))
    assert_int_equal(-200, -299.truncate(-2))
    assert_int_equal(-300, -300.truncate(-2))
    assert_int_equal(+20 * 10**70, (+25 * 10**70).truncate(-71))
    assert_int_equal(-20 * 10**70, (-25 * 10**70).truncate(-71))
    assert_int_equal(+20 * 10**70, (+25 * 10**70 - 1).truncate(-71))
    assert_int_equal(-20 * 10**70, (-25 * 10**70 + 1).truncate(-71))

    assert_int_equal(1111_1111_1111_1111_1111_1111_1111_1110, 1111_1111_1111_1111_1111_1111_1111_1111.truncate(-1))
    assert_int_equal(-1111_1111_1111_1111_1111_1111_1111_1110, (-1111_1111_1111_1111_1111_1111_1111_1111).truncate(-1))

    assert_int_equal(1111_1111_1111_1111_1111_1111_1111_1111, 1111_1111_1111_1111_1111_1111_1111_1111.truncate(1))
    assert_int_equal(10**400, (10**400).truncate(1))
  end

  MimicInteger = Struct.new(:to_int)
  module CoercionToInt
    def coerce(other)
      [other, to_int]
    end
  end

  def test_bitwise_and_with_integer_mimic_object
    obj = MimicInteger.new(10)
    assert_raise(TypeError, '[ruby-core:39491]') { 3 & obj }
    obj.extend(CoercionToInt)
    assert_equal(3 & 10, 3 & obj)
  end

  def test_bitwise_or_with_integer_mimic_object
    obj = MimicInteger.new(10)
    assert_raise(TypeError, '[ruby-core:39491]') { 3 | obj }
    obj.extend(CoercionToInt)
    assert_equal(3 | 10, 3 | obj)
  end

  def test_bitwise_xor_with_integer_mimic_object
    obj = MimicInteger.new(10)
    assert_raise(TypeError, '[ruby-core:39491]') { 3 ^ obj }
    obj.extend(CoercionToInt)
    assert_equal(3 ^ 10, 3 ^ obj)
  end

  module CoercionToSelf
    def coerce(other)
     [self.class.new(other), self]
    end
  end

  def test_bitwise_and_with_integer_coercion
    obj = Struct.new(:value) do
      include(CoercionToSelf)
      def &(other)
        self.value & other.value
      end
    end.new(10)
    assert_equal(3 & 10, 3 & obj)
  end

  def test_bitwise_or_with_integer_coercion
    obj = Struct.new(:value) do
      include(CoercionToSelf)
      def |(other)
        self.value | other.value
      end
    end.new(10)
    assert_equal(3 | 10, 3 | obj)
  end

  def test_bitwise_xor_with_integer_coercion
    obj = Struct.new(:value) do
      include(CoercionToSelf)
      def ^(other)
        self.value ^ other.value
      end
    end.new(10)
    assert_equal(3 ^ 10, 3 ^ obj)
  end

  def test_bit_length
    assert_equal(13, (-2**12-1).bit_length)
    assert_equal(12, (-2**12).bit_length)
    assert_equal(12, (-2**12+1).bit_length)
    assert_equal(9, -0x101.bit_length)
    assert_equal(8, -0x100.bit_length)
    assert_equal(8, -0xff.bit_length)
    assert_equal(1, -2.bit_length)
    assert_equal(0, -1.bit_length)
    assert_equal(0, 0.bit_length)
    assert_equal(1, 1.bit_length)
    assert_equal(8, 0xff.bit_length)
    assert_equal(9, 0x100.bit_length)
    assert_equal(9, 0x101.bit_length)
    assert_equal(12, (2**12-1).bit_length)
    assert_equal(13, (2**12).bit_length)
    assert_equal(13, (2**12+1).bit_length)

    assert_equal(10001, (-2**10000-1).bit_length)
    assert_equal(10000, (-2**10000).bit_length)
    assert_equal(10000, (-2**10000+1).bit_length)
    assert_equal(10000, (2**10000-1).bit_length)
    assert_equal(10001, (2**10000).bit_length)
    assert_equal(10001, (2**10000+1).bit_length)

    2.upto(1000) {|i|
      n = 2**i
      assert_equal(i+1, (-n-1).bit_length, "(#{-n-1}).bit_length")
      assert_equal(i,   (-n).bit_length, "(#{-n}).bit_length")
      assert_equal(i,   (-n+1).bit_length, "(#{-n+1}).bit_length")
      assert_equal(i,   (n-1).bit_length, "#{n-1}.bit_length")
      assert_equal(i+1, (n).bit_length, "#{n}.bit_length")
      assert_equal(i+1, (n+1).bit_length, "#{n+1}.bit_length")
    }
  end

  def test_digits
    assert_equal([0], 0.digits)
    assert_equal([1], 1.digits)
    assert_equal([0, 9, 8, 7, 6, 5, 4, 3, 2, 1], 1234567890.digits)
    assert_equal([90, 78, 56, 34, 12], 1234567890.digits(100))
    assert_equal([10, 5, 6, 8, 0, 10, 8, 6, 1], 1234567890.digits(13))
  end

  def test_digits_for_negative_numbers
    assert_raise(Math::DomainError) { -1.digits }
    assert_raise(Math::DomainError) { -1234567890.digits }
    assert_raise(Math::DomainError) { -1234567890.digits(100) }
    assert_raise(Math::DomainError) { -1234567890.digits(13) }
  end

  def test_digits_for_invalid_base_numbers
    assert_raise(ArgumentError) { 10.digits(-1) }
    assert_raise(ArgumentError) { 10.digits(0) }
    assert_raise(ArgumentError) { 10.digits(1) }
  end

  def test_digits_for_non_integral_base_numbers
    assert_equal([1], 1.digits(10r))
    assert_equal([1], 1.digits(10.0))
    assert_raise(RangeError) { 10.digits(10+1i) }
  end

  def test_digits_for_non_numeric_base_argument
    assert_raise(TypeError) { 10.digits("10") }
    assert_raise(TypeError) { 10.digits("a") }

    class << (o = Object.new)
      def to_int
        10
      end
    end
    assert_equal([0, 1], 10.digits(o))
  end

  def test_square_root
    assert_raise(TypeError) {Integer.sqrt("x")}
    assert_raise(Math::DomainError) {Integer.sqrt(-1)}
    assert_equal(0, Integer.sqrt(0))
    (1...4).each {|i| assert_equal(1, Integer.sqrt(i))}
    (4...9).each {|i| assert_equal(2, Integer.sqrt(i))}
    (9...16).each {|i| assert_equal(3, Integer.sqrt(i))}
    (1..40).each do |i|
      mesg = "10**#{i}"
      s = Integer.sqrt(n = 10**i)
      if i.even?
        assert_equal(10**(i/2), Integer.sqrt(n), mesg)
      else
        assert_include((s**2)...(s+1)**2, n, mesg)
      end
    end
    50.step(400, 10) do |i|
      exact = 10**(i/2)
      x = 10**i
      assert_equal(exact, Integer.sqrt(x), "10**#{i}")
      assert_equal(exact, Integer.sqrt(x+1), "10**#{i}+1")
      assert_equal(exact-1, Integer.sqrt(x-1), "10**#{i}-1")
    end

    bug13440 = '[ruby-core:80696] [Bug #13440]'
    failures = []
    0.step(to: 50, by: 0.05) do |i|
      n = (10**i).to_i
      root = Integer.sqrt(n)
      failures << n  unless root*root <= n && (root+1)*(root+1) > n
    end
    assert_empty(failures, bug13440)
  end

  def test_fdiv
    assert_equal(1.0, 1.fdiv(1))
    assert_equal(0.5, 1.fdiv(2))
  end

  def test_obj_fdiv
    o = Object.new
    def o.coerce(x); [x, 0.5]; end
    assert_equal(2.0, 1.fdiv(o))
    o = Object.new
    def o.coerce(x); [self, x]; end
    def o.fdiv(x); 1; end
    assert_equal(1.0, 1.fdiv(o))
  end
end
