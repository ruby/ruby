require_relative '../../spec_helper'

describe "Integer#[]" do
  context "fixnum" do
    it "behaves like (n >> b) & 1" do
      0b101[1].should == 0
      0b101[2].should == 1
    end

    it "returns 1 if the nth bit is set" do
      15[1].should == 1
    end

    it "returns 1 if the nth bit is set (in two's-complement representation)" do
      (-1)[1].should == 1
    end

    it "returns 0 if the nth bit is not set" do
      8[2].should == 0
    end

    it "returns 0 if the nth bit is not set (in two's-complement representation)" do
      (-2)[0].should == 0
    end

    it "returns 0 if the nth bit is greater than the most significant bit" do
      2[3].should == 0
    end

    it "returns 1 if self is negative and the nth bit is greater than the most significant bit" do
      (-1)[3].should == 1
    end

    it "returns 0 when passed a negative argument" do
      3[-1].should == 0
      (-1)[-1].should == 0
    end

    it "calls #to_int to convert the argument to an Integer and returns 1 if the nth bit is set" do
      obj = mock('1')
      obj.should_receive(:to_int).and_return(1)

      2[obj].should == 1
    end

    it "calls #to_int to convert the argument to an Integer and returns 0 if the nth bit is set" do
      obj = mock('0')
      obj.should_receive(:to_int).and_return(0)

      2[obj].should == 0
    end

    it "accepts a Float argument and returns 0 if the bit at the truncated value is not set" do
      13[1.3].should == 0
    end

    it "accepts a Float argument and returns 1 if the bit at the truncated value is set" do
      13[2.1].should == 1
    end

    it "raises a TypeError when passed a String" do
      -> { 3["3"] }.should raise_error(TypeError)
    end

    it "raises a TypeError when #to_int does not return an Integer" do
      obj = mock('asdf')
      obj.should_receive(:to_int).and_return("asdf")
      -> { 3[obj] }.should raise_error(TypeError)
    end

    it "calls #to_int to coerce a String to an Integer and returns 0" do
      obj = mock('bignum value')
      obj.should_receive(:to_int).and_return(bignum_value)

      3[obj].should == 0
    end

    it "returns 0 when passed a Float in the range of an Integer" do
      3[bignum_value.to_f].should == 0
    end

    ruby_version_is "2.7" do
      context "when index and length passed" do
        it "returns specified number of bits from specified position" do
          0b101001101[2, 4].should ==    0b0011
          0b101001101[2, 5].should ==   0b10011
          0b101001101[2, 7].should == 0b1010011
        end

        it "ensures n[i, len] equals to (n >> i) & ((1 << len) - 1)" do
          n = 0b101001101; i = 2; len = 4
          n[i, len].should == (n >> i) & ((1 << len) - 1)
        end

        it "moves start position to the most significant bits when negative index passed" do
          0b000001[-1, 4].should == 0b10
          0b000001[-2, 4].should == 0b100
          0b000001[-3, 4].should == 0b1000
        end

        it "ignores negative length" do
          0b101001101[1, -1].should == 0b10100110
          0b101001101[2, -1].should == 0b1010011
          0b101001101[3, -1].should == 0b101001

          0b101001101[3,   -5].should == 0b101001
          0b101001101[3,  -15].should == 0b101001
          0b101001101[3, -125].should == 0b101001
        end
      end

      context "when range passed" do
        it "returns bits specified by range" do
          0b101001101[2..5].should ==    0b0011
          0b101001101[2..6].should ==   0b10011
          0b101001101[2..8].should == 0b1010011
        end

        it "ensures n[i..j] equals to (n >> i) & ((1 << (j - i + 1)) - 1)" do
          n = 0b101001101; i = 2; j = 5
          n[i..j].should == (n >> i) & ((1 << (j - i + 1)) - 1)
        end

        it "ensures n[i..] equals to (n >> i)" do
          eval("0b101001101[3..]").should == 0b101001101 >> 3
        end

        it "moves lower boundary to the most significant bits when negative value passed" do
          0b000001[-1, 4].should == 0b10
          0b000001[-2, 4].should == 0b100
          0b000001[-3, 4].should == 0b1000
        end

        it "ignores negative upper boundary" do
          0b101001101[1..-1].should == 0b10100110
          0b101001101[1..-2].should == 0b10100110
          0b101001101[1..-3].should == 0b10100110
        end

        it "ignores upper boundary smaller than lower boundary" do
          0b101001101[4..1].should == 0b10100
          0b101001101[4..2].should == 0b10100
          0b101001101[4..3].should == 0b10100
        end

        it "raises FloatDomainError if any boundary is infinity" do
          -> { 0x0001[3..Float::INFINITY] }.should raise_error(FloatDomainError, /Infinity/)
          -> { 0x0001[-Float::INFINITY..3] }.should raise_error(FloatDomainError, /-Infinity/)
        end

        context "when passed (..i)" do
          it "returns 0 if all i bits equal 0" do
            eval("0b10000[..1]").should == 0
            eval("0b10000[..2]").should == 0
            eval("0b10000[..3]").should == 0
          end

          it "raises ArgumentError if any of i bit equals 1" do
            -> {
              eval("0b111110[..3]")
            }.should raise_error(ArgumentError, /The beginless range for Integer#\[\] results in infinity/)
          end
        end
      end
    end
  end

  context "bignum" do
    before :each do
      @bignum = bignum_value(4996)
    end

    it "returns the nth bit in the binary representation of self" do
      @bignum[2].should == 1
      @bignum[9.2].should == 1
      @bignum[21].should == 0
      @bignum[0xffffffff].should == 0
      @bignum[-0xffffffff].should == 0
    end

    it "tries to convert the given argument to an Integer using #to_int" do
      @bignum[1.3].should == @bignum[1]

      (obj = mock('2')).should_receive(:to_int).at_least(1).and_return(2)
      @bignum[obj].should == 1
    end

    it "raises a TypeError when the given argument can't be converted to Integer" do
      obj = mock('asdf')
      -> { @bignum[obj] }.should raise_error(TypeError)

      obj.should_receive(:to_int).and_return("asdf")
      -> { @bignum[obj] }.should raise_error(TypeError)
    end
  end
end
