require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe :kernel_integer, shared: true do
  it "returns a Bignum for a Bignum" do
    Integer(2e100).should == 2e100
  end

  it "returns a Fixnum for a Fixnum" do
    Integer(100).should == 100
  end

  ruby_version_is ""..."2.6" do
    it "uncritically return the value of to_int even if it is not an Integer" do
      obj = mock("object")
      obj.should_receive(:to_int).and_return("1")
      obj.should_not_receive(:to_i)
      Integer(obj).should == "1"
    end
  end

  ruby_version_is "2.6" do
    it "raises a TypeError when to_int returns not-an-Integer object and to_i returns nil" do
      obj = mock("object")
      obj.should_receive(:to_int).and_return("1")
      obj.should_receive(:to_i).and_return(nil)
      -> { Integer(obj) }.should raise_error(TypeError)
    end

    it "return a result of to_i when to_int does not return an Integer" do
      obj = mock("object")
      obj.should_receive(:to_int).and_return("1")
      obj.should_receive(:to_i).and_return(42)
      Integer(obj).should == 42
    end
  end

  it "raises a TypeError when passed nil" do
    -> { Integer(nil) }.should raise_error(TypeError)
  end

  it "returns a Fixnum or Bignum object" do
    Integer(2).should be_an_instance_of(Fixnum)
    Integer(9**99).should be_an_instance_of(Bignum)
  end

  it "truncates Floats" do
    Integer(3.14).should == 3
    Integer(90.8).should == 90
  end

  it "calls to_i on Rationals" do
    Integer(Rational(8,3)).should == 2
    Integer(3.quo(2)).should == 1
  end

  it "returns the value of to_int if the result is a Fixnum" do
    obj = mock("object")
    obj.should_receive(:to_int).and_return(1)
    obj.should_not_receive(:to_i)
    Integer(obj).should == 1
  end

  it "returns the value of to_int if the result is a Bignum" do
    obj = mock("object")
    obj.should_receive(:to_int).and_return(2 * 10**100)
    obj.should_not_receive(:to_i)
    Integer(obj).should == 2 * 10**100
  end

  it "calls to_i on an object whose to_int returns nil" do
    obj = mock("object")
    obj.should_receive(:to_int).and_return(nil)
    obj.should_receive(:to_i).and_return(1)
    Integer(obj).should == 1
  end

  it "raises a TypeError if to_i returns a value that is not an Integer" do
    obj = mock("object")
    obj.should_receive(:to_i).and_return("1")
    -> { Integer(obj) }.should raise_error(TypeError)
  end

  it "raises a TypeError if no to_int or to_i methods exist" do
    obj = mock("object")
    -> { Integer(obj) }.should raise_error(TypeError)
  end

  it "raises a TypeError if to_int returns nil and no to_i exists" do
    obj = mock("object")
    obj.should_receive(:to_i).and_return(nil)
    -> { Integer(obj) }.should raise_error(TypeError)
  end

  it "raises a FloatDomainError when passed NaN" do
    -> { Integer(nan_value) }.should raise_error(FloatDomainError)
  end

  it "raises a FloatDomainError when passed Infinity" do
    -> { Integer(infinity_value) }.should raise_error(FloatDomainError)
  end

  ruby_version_is "2.6" do
    describe "when passed exception: false" do
      describe "and to_i returns a value that is not an Integer" do
        it "swallows an error" do
          obj = mock("object")
          obj.should_receive(:to_i).and_return("1")
          Integer(obj, exception: false).should == nil
        end
      end

      describe "and no to_int or to_i methods exist" do
        it "swallows an error" do
          obj = mock("object")
          Integer(obj, exception: false).should == nil
        end
      end

      describe "and to_int returns nil and no to_i exists" do
        it "swallows an error" do
          obj = mock("object")
          obj.should_receive(:to_i).and_return(nil)
          Integer(obj, exception: false).should == nil
        end
      end

      describe "and passed NaN" do
        it "swallows an error" do
          Integer(nan_value, exception: false).should == nil
        end
      end

      describe "and passed Infinity" do
        it "swallows an error" do
          Integer(infinity_value, exception: false).should == nil
        end
      end

      describe "and passed nil" do
        it "swallows an error" do
          Integer(nil, exception: false).should == nil
        end
      end

      describe "and passed a String that contains numbers" do
        it "normally parses it and returns an Integer" do
          Integer("42", exception: false).should == 42
        end
      end

      describe "and passed a String that can't be converted to an Integer" do
        it "swallows an error" do
          Integer("abc", exception: false).should == nil
        end
      end
    end
  end
end

describe "Integer() given a String", shared: true do
  it "raises an ArgumentError if the String is a null byte" do
    -> { Integer("\0") }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError if the String starts with a null byte" do
    -> { Integer("\01") }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError if the String ends with a null byte" do
    -> { Integer("1\0") }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError if the String contains a null byte" do
    -> { Integer("1\01") }.should raise_error(ArgumentError)
  end

  it "ignores leading whitespace" do
    Integer(" 1").should == 1
    Integer("   1").should == 1
    Integer("\t\n1").should == 1
  end

  it "ignores trailing whitespace" do
    Integer("1 ").should == 1
    Integer("1   ").should == 1
    Integer("1\t\n").should == 1
  end

  it "raises an ArgumentError if there are leading _s" do
    -> { Integer("_1") }.should raise_error(ArgumentError)
    -> { Integer("___1") }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError if there are trailing _s" do
    -> { Integer("1_") }.should raise_error(ArgumentError)
    -> { Integer("1___") }.should raise_error(ArgumentError)
  end

  it "ignores an embedded _" do
    Integer("1_1").should == 11
  end

  it "raises an ArgumentError if there are multiple embedded _s" do
    -> { Integer("1__1") }.should raise_error(ArgumentError)
    -> { Integer("1___1") }.should raise_error(ArgumentError)
  end

  it "ignores a single leading +" do
    Integer("+1").should == 1
  end

  it "raises an ArgumentError if there is a space between the + and number" do
    -> { Integer("+ 1") }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError if there are multiple leading +s" do
    -> { Integer("++1") }.should raise_error(ArgumentError)
    -> { Integer("+++1") }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError if there are trailing +s" do
    -> { Integer("1+") }.should raise_error(ArgumentError)
    -> { Integer("1+++") }.should raise_error(ArgumentError)
  end

  it "makes the number negative if there's a leading -" do
    Integer("-1").should == -1
  end

  it "raises an ArgumentError if there are multiple leading -s" do
    -> { Integer("--1") }.should raise_error(ArgumentError)
    -> { Integer("---1") }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError if there are trailing -s" do
    -> { Integer("1-") }.should raise_error(ArgumentError)
    -> { Integer("1---") }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError if there is a period" do
    -> { Integer("0.0") }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError for an empty String" do
    -> { Integer("") }.should raise_error(ArgumentError)
  end

  ruby_version_is "2.6" do
    describe "when passed exception: false" do
      describe "and multiple leading -s" do
        it "swallows an error" do
          Integer("---1", exception: false).should == nil
        end
      end

      describe "and multiple trailing -s" do
        it "swallows an error" do
          Integer("1---", exception: false).should == nil
        end
      end

      describe "and an argument that contains a period" do
        it "swallows an error" do
          Integer("0.0", exception: false).should == nil
        end
      end

      describe "and an empty string" do
        it "swallows an error" do
          Integer("", exception: false).should == nil
        end
      end
    end
  end

  it "parses the value as 0 if the string consists of a single zero character" do
    Integer("0").should == 0
  end

  %w(x X).each do |x|
    it "parses the value as a hex number if there's a leading 0#{x}" do
      Integer("0#{x}1").should == 0x1
      Integer("0#{x}dd").should == 0xdd
    end

    it "is a positive hex number if there's a leading +0#{x}" do
      Integer("+0#{x}1").should == 0x1
      Integer("+0#{x}dd").should == 0xdd
    end

    it "is a negative hex number if there's a leading -0#{x}" do
      Integer("-0#{x}1").should == -0x1
      Integer("-0#{x}dd").should == -0xdd
    end

    it "raises an ArgumentError if the number cannot be parsed as hex" do
      -> { Integer("0#{x}g") }.should raise_error(ArgumentError)
    end
  end

  %w(b B).each do |b|
    it "parses the value as a binary number if there's a leading 0#{b}" do
      Integer("0#{b}1").should == 0b1
      Integer("0#{b}10").should == 0b10
    end

    it "is a positive binary number if there's a leading +0#{b}" do
      Integer("+0#{b}1").should == 0b1
      Integer("+0#{b}10").should == 0b10
    end

    it "is a negative binary number if there's a leading -0#{b}" do
      Integer("-0#{b}1").should == -0b1
      Integer("-0#{b}10").should == -0b10
    end

    it "raises an ArgumentError if the number cannot be parsed as binary" do
      -> { Integer("0#{b}2") }.should raise_error(ArgumentError)
    end
  end

  ["o", "O", ""].each do |o|
    it "parses the value as an octal number if there's a leading 0#{o}" do
      Integer("0#{o}1").should == 0O1
      Integer("0#{o}10").should == 0O10
    end

    it "is a positive octal number if there's a leading +0#{o}" do
      Integer("+0#{o}1").should == 0O1
      Integer("+0#{o}10").should == 0O10
    end

    it "is a negative octal number if there's a leading -0#{o}" do
      Integer("-0#{o}1").should == -0O1
      Integer("-0#{o}10").should == -0O10
    end

    it "raises an ArgumentError if the number cannot be parsed as octal" do
      -> { Integer("0#{o}9") }.should raise_error(ArgumentError)
    end
  end

  %w(D d).each do |d|
    it "parses the value as a decimal number if there's a leading 0#{d}" do
      Integer("0#{d}1").should == 1
      Integer("0#{d}10").should == 10
    end

    it "is a positive decimal number if there's a leading +0#{d}" do
      Integer("+0#{d}1").should == 1
      Integer("+0#{d}10").should == 10
    end

    it "is a negative decimal number if there's a leading -0#{d}" do
      Integer("-0#{d}1").should == -1
      Integer("-0#{d}10").should == -10
    end

    it "raises an ArgumentError if the number cannot be parsed as decimal" do
      -> { Integer("0#{d}a") }.should raise_error(ArgumentError)
    end
  end
end

describe "Integer() given a String and base", shared: true do
  it "raises an ArgumentError if the String is a null byte" do
    -> { Integer("\0", 2) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError if the String starts with a null byte" do
    -> { Integer("\01", 3) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError if the String ends with a null byte" do
    -> { Integer("1\0", 4) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError if the String contains a null byte" do
    -> { Integer("1\01", 5) }.should raise_error(ArgumentError)
  end

  it "ignores leading whitespace" do
    Integer(" 16", 16).should == 22
    Integer("   16", 16).should == 22
    Integer("\t\n16", 16).should == 22
  end

  it "ignores trailing whitespace" do
    Integer("16 ", 16).should == 22
    Integer("16   ", 16).should == 22
    Integer("16\t\n", 16).should == 22
  end

  it "raises an ArgumentError if there are leading _s" do
    -> { Integer("_1", 7) }.should raise_error(ArgumentError)
    -> { Integer("___1", 7) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError if there are trailing _s" do
    -> { Integer("1_", 12) }.should raise_error(ArgumentError)
    -> { Integer("1___", 12) }.should raise_error(ArgumentError)
  end

  it "ignores an embedded _" do
    Integer("1_1", 4).should == 5
  end

  it "raises an ArgumentError if there are multiple embedded _s" do
    -> { Integer("1__1", 4) }.should raise_error(ArgumentError)
    -> { Integer("1___1", 4) }.should raise_error(ArgumentError)
  end

  it "ignores a single leading +" do
    Integer("+10", 3).should == 3
  end

  it "raises an ArgumentError if there is a space between the + and number" do
    -> { Integer("+ 1", 3) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError if there are multiple leading +s" do
    -> { Integer("++1", 3) }.should raise_error(ArgumentError)
    -> { Integer("+++1", 3) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError if there are trailing +s" do
    -> { Integer("1+", 3) }.should raise_error(ArgumentError)
    -> { Integer("1+++", 12) }.should raise_error(ArgumentError)
  end

  it "makes the number negative if there's a leading -" do
    Integer("-19", 20).should == -29
  end

  it "raises an ArgumentError if there are multiple leading -s" do
    -> { Integer("--1", 9) }.should raise_error(ArgumentError)
    -> { Integer("---1", 9) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError if there are trailing -s" do
    -> { Integer("1-", 12) }.should raise_error(ArgumentError)
    -> { Integer("1---", 12) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError if there is a period" do
    -> { Integer("0.0", 3) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError for an empty String" do
    -> { Integer("", 12) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError for a base of 1" do
    -> { Integer("1", 1) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError for a base of 37" do
    -> { Integer("1", 37) }.should raise_error(ArgumentError)
  end

  it "accepts wholly lowercase alphabetic strings for bases > 10" do
    Integer('ab',12).should == 131
    Integer('af',20).should == 215
    Integer('ghj',30).should == 14929
  end

  it "accepts wholly uppercase alphabetic strings for bases > 10" do
    Integer('AB',12).should == 131
    Integer('AF',20).should == 215
    Integer('GHJ',30).should == 14929
  end

  it "accepts mixed-case alphabetic strings for bases > 10" do
    Integer('Ab',12).should == 131
    Integer('aF',20).should == 215
    Integer('GhJ',30).should == 14929
  end

  it "accepts alphanumeric strings for bases > 10" do
    Integer('a3e',19).should == 3681
    Integer('12q',31).should == 1049
    Integer('c00o',29).should == 292692
  end

  it "raises an ArgumentError for letters invalid in the given base" do
    -> { Integer('z',19) }.should raise_error(ArgumentError)
    -> { Integer('c00o',2) }.should raise_error(ArgumentError)
  end

  %w(x X).each do |x|
    it "parses the value as a hex number if there's a leading 0#{x} and a base of 16" do
      Integer("0#{x}10", 16).should == 16
      Integer("0#{x}dd", 16).should == 221
    end

    it "is a positive hex number if there's a leading +0#{x} and base of 16" do
      Integer("+0#{x}1", 16).should == 0x1
      Integer("+0#{x}dd", 16).should == 0xdd
    end

    it "is a negative hex number if there's a leading -0#{x} and a base of 16" do
      Integer("-0#{x}1", 16).should == -0x1
      Integer("-0#{x}dd", 16).should == -0xdd
    end

    2.upto(15) do |base|
      it "raises an ArgumentError if the number begins with 0#{x} and the base is #{base}" do
        -> { Integer("0#{x}1", base) }.should raise_error(ArgumentError)
      end
    end

    it "raises an ArgumentError if the number cannot be parsed as hex and the base is 16" do
      -> { Integer("0#{x}g", 16) }.should raise_error(ArgumentError)
    end
  end

  %w(b B).each do |b|
    it "parses the value as a binary number if there's a leading 0#{b} and the base is 2" do
      Integer("0#{b}1", 2).should == 0b1
      Integer("0#{b}10", 2).should == 0b10
    end

    it "is a positive binary number if there's a leading +0#{b} and a base of 2" do
      Integer("+0#{b}1", 2).should == 0b1
      Integer("+0#{b}10", 2).should == 0b10
    end

    it "is a negative binary number if there's a leading -0#{b} and a base of 2" do
      Integer("-0#{b}1", 2).should == -0b1
      Integer("-0#{b}10", 2).should == -0b10
    end

    it "raises an ArgumentError if the number cannot be parsed as binary and the base is 2" do
      -> { Integer("0#{b}2", 2) }.should raise_error(ArgumentError)
    end
  end

  ["o", "O"].each do |o|
    it "parses the value as an octal number if there's a leading 0#{o} and a base of 8" do
      Integer("0#{o}1", 8).should == 0O1
      Integer("0#{o}10", 8).should == 0O10
    end

    it "is a positive octal number if there's a leading +0#{o} and a base of 8" do
      Integer("+0#{o}1", 8).should == 0O1
      Integer("+0#{o}10", 8).should == 0O10
    end

    it "is a negative octal number if there's a leading -0#{o} and a base of 8" do
      Integer("-0#{o}1", 8).should == -0O1
      Integer("-0#{o}10", 8).should == -0O10
    end

    it "raises an ArgumentError if the number cannot be parsed as octal and the base is 8" do
      -> { Integer("0#{o}9", 8) }.should raise_error(ArgumentError)
    end

    2.upto(7) do |base|
      it "raises an ArgumentError if the number begins with 0#{o} and the base is #{base}" do
        -> { Integer("0#{o}1", base) }.should raise_error(ArgumentError)
      end
    end
  end

  %w(D d).each do |d|
    it "parses the value as a decimal number if there's a leading 0#{d} and a base of 10" do
      Integer("0#{d}1", 10).should == 1
      Integer("0#{d}10",10).should == 10
    end

    it "is a positive decimal number if there's a leading +0#{d} and a base of 10" do
      Integer("+0#{d}1", 10).should == 1
      Integer("+0#{d}10", 10).should == 10
    end

    it "is a negative decimal number if there's a leading -0#{d} and a base of 10" do
      Integer("-0#{d}1", 10).should == -1
      Integer("-0#{d}10", 10).should == -10
    end

    it "raises an ArgumentError if the number cannot be parsed as decimal and the base is 10" do
      -> { Integer("0#{d}a", 10) }.should raise_error(ArgumentError)
    end

    2.upto(9) do |base|
      it "raises an ArgumentError if the number begins with 0#{d} and the base is #{base}" do
        -> { Integer("0#{d}1", base) }.should raise_error(ArgumentError)
      end
    end

    it "raises an ArgumentError if a base is given for a non-String value" do
      -> { Integer(98, 15) }.should raise_error(ArgumentError)
    end
  end

  ruby_version_is "2.6" do
    describe "when passed exception: false" do
      describe "and valid argument" do
        it "returns an Integer number" do
          Integer("100", 10, exception: false).should == 100
          Integer("100", 2, exception: false).should == 4
        end
      end

      describe "and invalid argument" do
        it "swallows an error" do
          Integer("999", 2, exception: false).should == nil
          Integer("abc", 10, exception: false).should == nil
        end
      end
    end
  end
end

describe :kernel_Integer, shared: true do
  it "raises an ArgumentError when the String contains digits out of range of radix 2" do
    str = "23456789abcdefghijklmnopqrstuvwxyz"
    -> { @object.send(@method, str, 2) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 3" do
    str = "3456789abcdefghijklmnopqrstuvwxyz"
    -> { @object.send(@method, str, 3) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 4" do
    str = "456789abcdefghijklmnopqrstuvwxyz"
    -> { @object.send(@method, str, 4) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 5" do
    str = "56789abcdefghijklmnopqrstuvwxyz"
    -> { @object.send(@method, str, 5) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 6" do
    str = "6789abcdefghijklmnopqrstuvwxyz"
    -> { @object.send(@method, str, 6) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 7" do
    str = "789abcdefghijklmnopqrstuvwxyz"
    -> { @object.send(@method, str, 7) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 8" do
    str = "89abcdefghijklmnopqrstuvwxyz"
    -> { @object.send(@method, str, 8) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 9" do
    str = "9abcdefghijklmnopqrstuvwxyz"
    -> { @object.send(@method, str, 9) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 10" do
    str = "abcdefghijklmnopqrstuvwxyz"
    -> { @object.send(@method, str, 10) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 11" do
    str = "bcdefghijklmnopqrstuvwxyz"
    -> { @object.send(@method, str, 11) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 12" do
    str = "cdefghijklmnopqrstuvwxyz"
    -> { @object.send(@method, str, 12) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 13" do
    str = "defghijklmnopqrstuvwxyz"
    -> { @object.send(@method, str, 13) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 14" do
    str = "efghijklmnopqrstuvwxyz"
    -> { @object.send(@method, str, 14) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 15" do
    str = "fghijklmnopqrstuvwxyz"
    -> { @object.send(@method, str, 15) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 16" do
    str = "ghijklmnopqrstuvwxyz"
    -> { @object.send(@method, str, 16) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 17" do
    str = "hijklmnopqrstuvwxyz"
    -> { @object.send(@method, str, 17) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 18" do
    str = "ijklmnopqrstuvwxyz"
    -> { @object.send(@method, str, 18) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 19" do
    str = "jklmnopqrstuvwxyz"
    -> { @object.send(@method, str, 19) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 20" do
    str = "klmnopqrstuvwxyz"
    -> { @object.send(@method, str, 20) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 21" do
    str = "lmnopqrstuvwxyz"
    -> { @object.send(@method, str, 21) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 22" do
    str = "mnopqrstuvwxyz"
    -> { @object.send(@method, str, 22) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 23" do
    str = "nopqrstuvwxyz"
    -> { @object.send(@method, str, 23) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 24" do
    str = "opqrstuvwxyz"
    -> { @object.send(@method, str, 24) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 25" do
    str = "pqrstuvwxyz"
    -> { @object.send(@method, str, 25) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 26" do
    str = "qrstuvwxyz"
    -> { @object.send(@method, str, 26) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 27" do
    str = "rstuvwxyz"
    -> { @object.send(@method, str, 27) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 28" do
    str = "stuvwxyz"
    -> { @object.send(@method, str, 28) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 29" do
    str = "tuvwxyz"
    -> { @object.send(@method, str, 29) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 30" do
    str = "uvwxyz"
    -> { @object.send(@method, str, 30) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 31" do
    str = "vwxyz"
    -> { @object.send(@method, str, 31) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 32" do
    str = "wxyz"
    -> { @object.send(@method, str, 32) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 33" do
    str = "xyz"
    -> { @object.send(@method, str, 33) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 34" do
    str = "yz"
    -> { @object.send(@method, str, 34) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 35" do
    str = "z"
    -> { @object.send(@method, str, 35) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError when the String contains digits out of range of radix 36" do
    -> { @object.send(@method, "{", 36) }.should raise_error(ArgumentError)
  end
end

describe "Kernel.Integer" do
  it_behaves_like :kernel_Integer, :Integer_method, KernelSpecs

  # TODO: fix these specs
  it_behaves_like :kernel_integer, :Integer, Kernel
  it_behaves_like "Integer() given a String", :Integer

  it_behaves_like "Integer() given a String and base", :Integer

  it "is a public method" do
    Kernel.Integer(10).should == 10
  end
end

describe "Kernel#Integer" do
  it_behaves_like :kernel_Integer, :Integer_function, KernelSpecs

  # TODO: fix these specs
  it_behaves_like :kernel_integer, :Integer, Object.new
  it_behaves_like "Integer() given a String", :Integer

  it_behaves_like "Integer() given a String and base", :Integer

  it "is a private method" do
    Kernel.should have_private_instance_method(:Integer)
  end
end
