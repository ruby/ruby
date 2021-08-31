# frozen_string_literal: false
require_relative 'test_optparse'

class TestOptionParser::Acceptable < TestOptionParser

  def setup
    super
    @opt.def_option("--integer VAL", Integer) { |v| @integer = v }
    @opt.def_option("--float VAL",   Float)   { |v| @float   = v }
    @opt.def_option("--numeric VAL", Numeric) { |v| @numeric = v }

    @opt.def_option("--decimal-integer VAL",
                    OptionParser::DecimalInteger) { |i| @decimal_integer = i }
    @opt.def_option("--octal-integer VAL",
                    OptionParser::OctalInteger)   { |i| @octal_integer   = i }
    @opt.def_option("--decimal-numeric VAL",
                    OptionParser::DecimalNumeric) { |i| @decimal_numeric = i }
  end

  def test_integer
    assert_equal(%w"", no_error {@opt.parse!(%w"--integer 0")})
    assert_equal(0, @integer)

    assert_equal(%w"", no_error {@opt.parse!(%w"--integer 0b10")})
    assert_equal(2, @integer)

    assert_equal(%w"", no_error {@opt.parse!(%w"--integer 077")})
    assert_equal(63, @integer)

    assert_equal(%w"", no_error {@opt.parse!(%w"--integer 10")})
    assert_equal(10, @integer)

    assert_equal(%w"", no_error {@opt.parse!(%w"--integer 0x3")})
    assert_equal(3, @integer)

    assert_raise(OptionParser::InvalidArgument) do
      @opt.parse!(%w"--integer 0b")
    end

    assert_raise(OptionParser::InvalidArgument) do
      @opt.parse!(%w"--integer 09")
    end

    assert_raise(OptionParser::InvalidArgument) do
      @opt.parse!(%w"--integer 0x")
    end

    assert_raise(OptionParser::InvalidArgument) do
      @opt.parse!(%w"--integer 1234xyz")
    end
  end

  def test_float
    assert_equal(%w"", no_error {@opt.parse!(%w"--float 0")})
    assert_in_epsilon(0.0, @float)

    assert_equal(%w"", no_error {@opt.parse!(%w"--float 0.0")})
    assert_in_epsilon(0.0, @float)

    assert_equal(%w"", no_error {@opt.parse!(%w"--float 1.2")})
    assert_in_epsilon(1.2, @float)

    assert_equal(%w"", no_error {@opt.parse!(%w"--float 1E2")})
    assert_in_epsilon(100, @float)

    assert_equal(%w"", no_error {@opt.parse!(%w"--float 1E-2")})
    assert_in_epsilon(0.01, @float)

    assert_raise(OptionParser::InvalidArgument) do
      @opt.parse!(%w"--float 0e")
    end

    assert_raise(OptionParser::InvalidArgument) do
      @opt.parse!(%w"--float 1.234xyz")
    end
  end

  def test_numeric
    assert_equal(%w"", no_error {@opt.parse!(%w"--numeric 0")})
    assert_equal(0, @numeric)

    assert_equal(%w"", no_error {@opt.parse!(%w"--numeric 0/1")})
    assert_equal(0, @numeric)

    assert_equal(%w"", no_error {@opt.parse!(%w"--numeric 1/2")})
    assert_equal(Rational(1, 2), @numeric)

    assert_equal(%w"", no_error {@opt.parse!(%w"--numeric 010")})
    assert_equal(8, @numeric)

    assert_equal(%w"", no_error {@opt.parse!(%w"--numeric 1.2/2.3")})
    assert_equal(Rational(12, 23), @numeric)

    assert_raise(OptionParser::InvalidArgument) do
      @opt.parse!(%w"--numeric 1/")
    end

    assert_raise(OptionParser::InvalidArgument) do
      @opt.parse!(%w"--numeric 12/34xyz")
    end

    assert_raise(OptionParser::InvalidArgument) do
      @opt.parse!(%w"--numeric 12x/34yz")
    end
  end

  def test_decimal_integer
    assert_equal(%w"", no_error {@opt.parse!(%w"--decimal-integer 0")})
    assert_equal(0, @decimal_integer)

    assert_equal(%w"", no_error {@opt.parse!(%w"--decimal-integer 10")})
    assert_equal(10, @decimal_integer)

    assert_equal(%w"", no_error {@opt.parse!(%w"--decimal-integer 010")})
    assert_equal(10, @decimal_integer)

    assert_equal(%w"", no_error {@opt.parse!(%w"--decimal-integer 09")})
    assert_equal(9, @decimal_integer)

    assert_raise(OptionParser::InvalidArgument) do
      @opt.parse!(%w"--decimal-integer 0b1")
    end

    assert_raise(OptionParser::InvalidArgument) do
      @opt.parse!(%w"--decimal-integer x")
    end

    assert_raise(OptionParser::InvalidArgument) do
      @opt.parse!(%w"--decimal-integer 1234xyz")
    end
  end

  def test_octal_integer
    assert_equal(%w"", no_error {@opt.parse!(%w"--octal-integer 0")})
    assert_equal(0, @octal_integer)

    assert_equal(%w"", no_error {@opt.parse!(%w"--octal-integer 6")})
    assert_equal(6, @octal_integer)

    assert_equal(%w"", no_error {@opt.parse!(%w"--octal-integer 07")})
    assert_equal(7, @octal_integer)

    assert_equal(%w"", no_error {@opt.parse!(%w"--octal-integer 10")})
    assert_equal(8, @octal_integer)

    assert_equal(%w"", no_error {@opt.parse!(%w"--octal-integer 011")})
    assert_equal(9, @octal_integer)

    assert_raise(OptionParser::InvalidArgument) do
      @opt.parse!(%w"--octal-integer 09")
    end

    assert_raise(OptionParser::InvalidArgument) do
      @opt.parse!(%w"--octal-integer 0b1")
    end

    assert_raise(OptionParser::InvalidArgument) do
      @opt.parse!(%w"--octal-integer x")
    end

    assert_raise(OptionParser::InvalidArgument) do
      @opt.parse!(%w"--octal-integer 01234xyz")
    end
  end

  def test_decimal_numeric
    assert_equal(%w"", no_error {@opt.parse!(%w"--decimal-numeric 0")})
    assert_equal(0, @decimal_numeric)

    assert_equal(%w"", no_error {@opt.parse!(%w"--decimal-numeric 01")})
    assert_equal(1, @decimal_numeric)

    assert_equal(%w"", no_error {@opt.parse!(%w"--decimal-numeric 1.2")})
    assert_in_delta(1.2, @decimal_numeric)

    assert_equal(%w"", no_error {@opt.parse!(%w"--decimal-numeric 1E2")})
    assert_in_delta(100.0, @decimal_numeric)

    assert_raise(OptionParser::InvalidArgument) do
      @opt.parse!(%w"--decimal-numeric 0b1")
    end

    e = assert_raise(OptionParser::InvalidArgument) do
      @opt.parse!(%w"--decimal-numeric 09")
    end

    assert_equal("invalid argument: --decimal-numeric 09", e.message)

    assert_raise(OptionParser::InvalidArgument) do
      @opt.parse!(%w"--decimal-integer 1234xyz")
    end

    assert_raise(OptionParser::InvalidArgument) do
      @opt.parse!(%w"--decimal-integer 12.34xyz")
    end
  end

end
