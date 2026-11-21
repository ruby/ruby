require_relative 'spec_helper'

load_extension("bignum")

max_long_long = RbConfig::LIMITS['LLONG_MAX']
min_long_long = RbConfig::LIMITS['LLONG_MIN']
max_ulong_long = RbConfig::LIMITS['ULLONG_MAX']

describe "CApiBignumSpecs" do
  before :each do
    @s = CApiBignumSpecs.new
    @max_long = max_long
    @min_long = min_long
    @max_long_long = max_long_long
    @min_long_long = min_long_long
    @max_ulong_long = max_ulong_long
    @max_ulong = max_ulong
    @max_len = max_rb_len_t
    @min_len = min_rb_len_t
    @max_fixnum = fixnum_max
    @min_fixnum = fixnum_min
  end

  describe "rb_big2long" do
    it "raises TypeError for a non-Bignum argument" do
      -> { @s.rb_big2long(0) }.should.raise(TypeError)
    end

    it "handles Bignum values at the long boundary" do
      if @max_long > @max_fixnum
        @s.rb_big2long(@max_long).should == @max_long
      else
        -> { @s.rb_big2long(@max_fixnum + 1) }.should.raise(RangeError)
      end

      if @min_long < @min_fixnum
        @s.rb_big2long(@min_long).should == @min_long
      else
        -> { @s.rb_big2long(@min_fixnum - 1) }.should.raise(RangeError)
      end

      if @max_len <= @max_long
        @s.rb_big2long(@max_len).should == @max_len
      else
        -> { @s.rb_big2long(@max_len) }.should.raise(RangeError)
      end

      if @min_len >= @min_long
        @s.rb_big2long(@min_len).should == @min_len
      else
        -> { @s.rb_big2long(@min_len) }.should.raise(RangeError)
      end
    end

    it "raises RangeError for Bignum values outside long range" do
      if @max_long >= @max_fixnum
        -> { @s.rb_big2long(@max_long + 1) }.should.raise(RangeError)
      else
        -> { @s.rb_big2long(@max_fixnum + 1) }.should.raise(RangeError)
      end

      if @min_long <= @min_fixnum
        -> { @s.rb_big2long(@min_long - 1) }.should.raise(RangeError)
      else
        -> { @s.rb_big2long(@min_fixnum - 1) }.should.raise(RangeError)
      end
    end
  end

  describe "rb_big2ll" do
    it "converts or rejects rb_len_t bounds according to long long range" do
      if @max_long_long > @max_fixnum
        @s.rb_big2ll(@max_long_long).should == @max_long_long
      else
        -> { @s.rb_big2ll(@max_fixnum + 1) }.should.raise(RangeError)
      end

      if @min_long_long < @min_fixnum
        @s.rb_big2ll(@min_long_long).should == @min_long_long
      else
        -> { @s.rb_big2ll(@min_fixnum - 1) }.should.raise(RangeError)
      end

      if @max_len <= @max_long_long
        @s.rb_big2ll(@max_len).should == @max_len
      else
        -> { @s.rb_big2ll(@max_len) }.should.raise(RangeError)
      end

      if @min_len >= @min_long_long
        @s.rb_big2ll(@min_len).should == @min_len
      else
        -> { @s.rb_big2ll(@min_len) }.should.raise(RangeError)
      end

      -> { @s.rb_big2ll(@max_long_long + 1) }.should.raise(RangeError)
      -> { @s.rb_big2ll(@min_long_long - 1) }.should.raise(RangeError)
    end
  end

  describe "rb_big2ull" do
    it "converts or rejects rb_len_t bounds according to unsigned long long range" do
      @s.rb_big2ull(@max_ulong_long).should == @max_ulong_long
      @s.rb_big2ull(@min_long_long).should == @min_long_long % (@max_ulong_long + 1)

      if @max_len <= @max_ulong_long
        @s.rb_big2ull(@max_len).should == @max_len
      else
        -> { @s.rb_big2ull(@max_len) }.should.raise(RangeError)
      end

      if @min_len >= @min_long_long
        @s.rb_big2ull(@min_len).should == @min_len % (@max_ulong_long + 1)
      else
        -> { @s.rb_big2ull(@min_len) }.should.raise(RangeError)
      end

      -> { @s.rb_big2ull(@max_ulong_long + 1) }.should.raise(RangeError)
      -> { @s.rb_big2ull(@min_long_long - 1) }.should.raise(RangeError)
    end
  end

  describe "rb_big2ulong" do
    it "converts or rejects rb_len_t bounds according to unsigned long range" do
      if @max_ulong > @max_fixnum
        @s.rb_big2ulong(@max_ulong).should == @max_ulong
        -> { @s.rb_big2ulong(@max_ulong + 1) }.should.raise(RangeError)
      else
        -> { @s.rb_big2ulong(@max_fixnum + 1) }.should.raise(RangeError)
      end

      if @min_long < @min_fixnum
        @s.rb_big2ulong(@min_long).should == -(@min_long)
        below_fixnum_min = @min_fixnum - 1
        @s.rb_big2ulong(below_fixnum_min).should ==
          below_fixnum_min % (@max_ulong + 1)
        -> { @s.rb_big2ulong(@min_long - 1) }.should.raise(RangeError)
      else
        -> { @s.rb_big2ulong(@min_fixnum - 1) }.should.raise(RangeError)
      end
    end
  end

  describe "rb_big2dbl" do
    it "converts a Bignum to a double value" do
      @s.rb_big2dbl(Float::MAX.to_i).eql?(Float::MAX).should == true
    end

    it "returns Infinity if the number is too big for a double" do
      huge_bignum = Float::MAX.to_i * 2
      @s.rb_big2dbl(huge_bignum).should == infinity_value
    end

    it "returns -Infinity if the number is negative and too big for a double" do
      huge_bignum = -(Float::MAX.to_i * 2)
      @s.rb_big2dbl(huge_bignum).should == -infinity_value
    end
  end

  describe "rb_big2str" do

    it "converts a Bignum to a string with base 10" do
      @s.rb_big2str(2**70, 10).eql?("1180591620717411303424").should == true
    end

    it "converts a Bignum to a string with a different base" do
      @s.rb_big2str(2**70, 16).eql?("400000000000000000").should == true
    end
  end

  describe "RBIGNUM_SIGN" do
    it "returns 1 for a positive Bignum" do
      @s.RBIGNUM_SIGN(bignum_value(1)).should == 1
    end

    it "returns 0 for a negative Bignum" do
      @s.RBIGNUM_SIGN(-bignum_value(1)).should == 0
    end
  end

  describe "rb_big_cmp" do
    it "compares a Bignum with a Bignum" do
      @s.rb_big_cmp(bignum_value, bignum_value(1)).should == -1
    end

    it "compares a Bignum with a Fixnum" do
      @s.rb_big_cmp(bignum_value, 5).should == 1
    end
  end

  describe "rb_big_pack" do
    it "packs a Bignum into an unsigned long" do
      val = @s.rb_big_pack(@max_ulong)
      val.should == @max_ulong
    end

    platform_is c_long_size: 64 do
      it "packs max_ulong into 2 ulongs to allow sign bit" do
        val = @s.rb_big_pack_length(@max_ulong)
        val.should == 2
        val = @s.rb_big_pack_array(@max_ulong, 2)
        val[0].should == @max_ulong
        val[1].should == 0
      end

      it "packs a 72-bit positive Bignum into 2 unsigned longs" do
        num = 2 ** 71
        val = @s.rb_big_pack_length(num)
        val.should == 2
      end

      it "packs a 72-bit positive Bignum into correct 2 longs" do
        num = 2 ** 71 + 1
        val = @s.rb_big_pack_array(num, 2)
        val[0].should == 1;
        val[1].should == 0x80;
      end

      it "packs a 72-bit negative Bignum into correct 2 longs" do
        num = -(2 ** 71 + 1)
        val = @s.rb_big_pack_array(num, @s.rb_big_pack_length(num))
        val[0].should == @max_ulong;
        val[1].should == @max_ulong - 0x80;
      end

      it "packs lower order bytes into least significant bytes of longs for positive bignum" do
        num = 0
        32.times { |i| num += i << (i * 8) }
        val = @s.rb_big_pack_array(num, @s.rb_big_pack_length(num))
        val.size.should == 4
        32.times do |i|
          a_long = val[i/8]
          a_byte = (a_long >> ((i % 8) * 8)) & 0xff
          a_byte.should ==  i
        end
      end

      it "packs lower order bytes into least significant bytes of longs for negative bignum" do
        num = 0
        32.times { |i| num += i << (i * 8) }
        num = -num
        val = @s.rb_big_pack_array(num, @s.rb_big_pack_length(num))
        val.size.should == 4
        expected_bytes = [0x00, 0xff, 0xfd, 0xfc, 0xfb, 0xfa, 0xf9, 0xf8,
                          0xf7, 0xf6, 0xf5, 0xf4, 0xf3, 0xf2, 0xf1, 0xf0,
                          0xef, 0xee, 0xed, 0xec, 0xeb, 0xea, 0xe9, 0xe8,
                          0xe7, 0xe6, 0xe5, 0xe4, 0xe3, 0xe2, 0xe1, 0xe0 ]
        32.times do |i|
          a_long = val[i/8]
          a_byte = (a_long >> ((i % 8) * 8)) & 0xff
          a_byte.should == expected_bytes[i]
        end
      end
    end
  end

  describe "rb_dbl2big" do
    it "returns a Fixnum for a Fixnum input value" do
      val = @s.rb_dbl2big(2)

      val.kind_of?(Integer).should == true
      val.should == 2
    end

    it "returns a Fixnum for a Float input value" do
      val = @s.rb_dbl2big(2.5)

      val.kind_of?(Integer).should == true
      val.should == 2
    end

    it "returns a Bignum for a large enough Float input value" do
      input = 219238102380912830988.5 # chosen by fair dice roll
      val   = @s.rb_dbl2big(input)

      val.kind_of?(Integer).should == true

      # This value is based on the output of a simple C extension that uses
      # rb_dbl2big() to convert the above input value to a Bignum.
      val.should == 219238102380912836608
    end

    it "raises FloatDomainError for Infinity values" do
      inf = 1.0 / 0

      -> { @s.rb_dbl2big(inf) }.should.raise(FloatDomainError)
    end

    it "raises FloatDomainError for NaN values" do
      nan = 0.0 / 0

      -> { @s.rb_dbl2big(nan) }.should.raise(FloatDomainError)
    end
  end
end
