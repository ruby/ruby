# -*- encoding: utf-8 -*-
# frozen_string_literal: false
require_relative '../../spec_helper'

describe "String#bytesplice" do
  it "raises IndexError when index is less than -bytesize" do
    -> { "hello".bytesplice(-6, 0, "xxx") }.should raise_error(IndexError, "index -6 out of string")
  end

  it "raises IndexError when index is greater than bytesize" do
    -> { "hello".bytesplice(6, 0, "xxx") }.should raise_error(IndexError, "index 6 out of string")
  end

  it "raises IndexError for negative length" do
    -> { "abc".bytesplice(0, -2, "") }.should raise_error(IndexError, "negative length -2")
  end

  it "replaces with integer indices" do
    "hello".bytesplice(-5, 0, "xxx").should == "xxxhello"
    "hello".bytesplice(0, 0, "xxx").should == "xxxhello"
    "hello".bytesplice(0, 1, "xxx").should == "xxxello"
    "hello".bytesplice(0, 5, "xxx").should == "xxx"
    "hello".bytesplice(0, 6, "xxx").should == "xxx"
  end

  it "raises RangeError when range left boundary is less than -bytesize" do
    -> { "hello".bytesplice(-6...-6, "xxx") }.should raise_error(RangeError, "-6...-6 out of range")
  end

  it "replaces with ranges" do
    "hello".bytesplice(-5...-5, "xxx").should == "xxxhello"
    "hello".bytesplice(0...0, "xxx").should == "xxxhello"
    "hello".bytesplice(0..0, "xxx").should == "xxxello"
    "hello".bytesplice(0...1, "xxx").should == "xxxello"
    "hello".bytesplice(0..1, "xxx").should == "xxxllo"
    "hello".bytesplice(0..-1, "xxx").should == "xxx"
    "hello".bytesplice(0...5, "xxx").should == "xxx"
    "hello".bytesplice(0...6, "xxx").should == "xxx"
  end

  it "raises TypeError when integer index is provided without length argument" do
    -> { "hello".bytesplice(0, "xxx") }.should raise_error(TypeError, "wrong argument type Integer (expected Range)")
  end

  it "replaces on an empty string" do
    "".bytesplice(0, 0, "").should == ""
    "".bytesplice(0, 0, "xxx").should == "xxx"
  end

  it "mutates self" do
    s = "hello"
    s.bytesplice(2, 1, "xxx").should.equal?(s)
  end

  it "raises when string is frozen" do
    s = "hello".freeze
    -> { s.bytesplice(2, 1, "xxx") }.should raise_error(FrozenError, "can't modify frozen String: \"hello\"")
  end

  ruby_version_is "3.3" do
    it "raises IndexError when str_index is less than -bytesize" do
      -> { "hello".bytesplice(2, 1, "HELLO", -6, 0) }.should raise_error(IndexError, "index -6 out of string")
    end

    it "raises IndexError when str_index is greater than bytesize" do
      -> { "hello".bytesplice(2, 1, "HELLO", 6, 0) }.should raise_error(IndexError, "index 6 out of string")
    end

    it "raises IndexError for negative str length" do
      -> { "abc".bytesplice(0, 1, "", 0, -2) }.should raise_error(IndexError, "negative length -2")
    end

    it "replaces with integer str indices" do
      "hello".bytesplice(1, 2, "HELLO", -5, 0).should == "hlo"
      "hello".bytesplice(1, 2, "HELLO", 0, 0).should == "hlo"
      "hello".bytesplice(1, 2, "HELLO", 0, 1).should == "hHlo"
      "hello".bytesplice(1, 2, "HELLO", 0, 5).should == "hHELLOlo"
      "hello".bytesplice(1, 2, "HELLO", 0, 6).should == "hHELLOlo"
    end

    it "raises RangeError when str range left boundary is less than -bytesize" do
      -> { "hello".bytesplice(0..1, "HELLO", -6...-6) }.should raise_error(RangeError, "-6...-6 out of range")
    end

    it "replaces with str ranges" do
      "hello".bytesplice(1..2, "HELLO", -5...-5).should == "hlo"
      "hello".bytesplice(1..2, "HELLO", 0...0).should == "hlo"
      "hello".bytesplice(1..2, "HELLO", 0..0).should == "hHlo"
      "hello".bytesplice(1..2, "HELLO", 0...1).should == "hHlo"
      "hello".bytesplice(1..2, "HELLO", 0..1).should == "hHElo"
      "hello".bytesplice(1..2, "HELLO", 0..-1).should == "hHELLOlo"
      "hello".bytesplice(1..2, "HELLO", 0...5).should == "hHELLOlo"
      "hello".bytesplice(1..2, "HELLO", 0...6).should == "hHELLOlo"
    end

    it "raises ArgumentError when integer str index is provided without str length argument" do
      -> { "hello".bytesplice(0, 1, "xxx", 0) }.should raise_error(ArgumentError, "wrong number of arguments (given 4, expected 2, 3, or 5)")
    end

    it "replaces on an empty string with str index/length" do
      "".bytesplice(0, 0, "", 0, 0).should == ""
      "".bytesplice(0, 0, "xxx", 0, 1).should == "x"
    end

    it "mutates self with substring and str index/length" do
      s = "hello"
      s.bytesplice(2, 1, "xxx", 1, 2).should.equal?(s)
      s.should.eql?("hexxlo")
    end

    it "raises when string is frozen and str index/length" do
      s = "hello".freeze
      -> { s.bytesplice(2, 1, "xxx", 0, 1) }.should raise_error(FrozenError, "can't modify frozen String: \"hello\"")
    end

    it "replaces on an empty string with str range" do
      "".bytesplice(0..0, "", 0..0).should == ""
      "".bytesplice(0..0, "xyz", 0..1).should == "xy"
    end

    it "mutates self with substring and str range" do
      s = "hello"
      s.bytesplice(2..2, "xyz", 1..2).should.equal?(s)
      s.should.eql?("heyzlo")
    end

    it "raises when string is frozen and str range" do
      s = "hello".freeze
      -> { s.bytesplice(2..2, "yzx", 0..1) }.should raise_error(FrozenError, "can't modify frozen String: \"hello\"")
    end
  end
end

describe "String#bytesplice with multibyte characters" do
  it "raises IndexError when index is out of byte size boundary" do
    -> { "こんにちは".bytesplice(-16, 0, "xxx") }.should raise_error(IndexError, "index -16 out of string")
  end

  it "raises IndexError when index is not on a codepoint boundary" do
    -> { "こんにちは".bytesplice(1, 0, "xxx") }.should raise_error(IndexError, "offset 1 does not land on character boundary")
  end

  it "raises IndexError when length is not matching the codepoint boundary" do
    -> { "こんにちは".bytesplice(0, 1, "xxx") }.should raise_error(IndexError, "offset 1 does not land on character boundary")
    -> { "こんにちは".bytesplice(0, 2, "xxx") }.should raise_error(IndexError, "offset 2 does not land on character boundary")
  end

  it "replaces with integer indices" do
    "こんにちは".bytesplice(-15, 0, "xxx").should == "xxxこんにちは"
    "こんにちは".bytesplice(0, 0, "xxx").should == "xxxこんにちは"
    "こんにちは".bytesplice(0, 3, "xxx").should == "xxxんにちは"
    "こんにちは".bytesplice(3, 3, "はは").should == "こははにちは"
    "こんにちは".bytesplice(15, 0, "xxx").should == "こんにちはxxx"
  end

  it "replaces with range" do
    "こんにちは".bytesplice(-15...-16, "xxx").should == "xxxこんにちは"
    "こんにちは".bytesplice(0...0, "xxx").should == "xxxこんにちは"
    "こんにちは".bytesplice(0..2, "xxx").should == "xxxんにちは"
    "こんにちは".bytesplice(0...3, "xxx").should == "xxxんにちは"
    "こんにちは".bytesplice(0..5, "xxx").should == "xxxにちは"
    "こんにちは".bytesplice(0..-1, "xxx").should == "xxx"
    "こんにちは".bytesplice(0...15, "xxx").should == "xxx"
    "こんにちは".bytesplice(0...18, "xxx").should == "xxx"
  end

  it "treats negative length for range as 0" do
    "こんにちは".bytesplice(0...-100, "xxx").should == "xxxこんにちは"
    "こんにちは".bytesplice(3...-100, "xxx").should == "こxxxんにちは"
    "こんにちは".bytesplice(-15...-100, "xxx").should == "xxxこんにちは"
  end

  it "raises when ranges not match codepoint boundaries" do
    -> { "こんにちは".bytesplice(0..0, "x") }.should raise_error(IndexError, "offset 1 does not land on character boundary")
    -> { "こんにちは".bytesplice(0..1, "x") }.should raise_error(IndexError, "offset 2 does not land on character boundary")
    # Begin is incorrect
    -> { "こんにちは".bytesplice(-4..-1, "x") }.should raise_error(IndexError, "offset 11 does not land on character boundary")
    -> { "こんにちは".bytesplice(-5..-1, "x") }.should raise_error(IndexError, "offset 10 does not land on character boundary")
    # End is incorrect
    -> { "こんにちは".bytesplice(-3..-2, "x") }.should raise_error(IndexError, "offset 14 does not land on character boundary")
    -> { "こんにちは".bytesplice(-3..-3, "x") }.should raise_error(IndexError, "offset 13 does not land on character boundary")
  end

  it "deals with a different encoded argument" do
    s = "こんにちは"
    s.encoding.should == Encoding::UTF_8
    sub = "xxxxxx"
    sub.force_encoding(Encoding::US_ASCII)

    result = s.bytesplice(0, 3, sub)
    result.should == "xxxxxxんにちは"
    result.encoding.should == Encoding::UTF_8

    s = "xxxxxx"
    s.force_encoding(Encoding::US_ASCII)
    sub = "こんにちは"
    sub.encoding.should == Encoding::UTF_8

    result = s.bytesplice(0, 3, sub)
    result.should == "こんにちはxxx"
    result.encoding.should == Encoding::UTF_8
  end

  ruby_version_is "3.3" do
    it "raises IndexError when str_index is out of byte size boundary" do
      -> { "こんにちは".bytesplice(3, 3, "こんにちは", -16, 0) }.should raise_error(IndexError, "index -16 out of string")
    end

    it "raises IndexError when str_index is not on a codepoint boundary" do
      -> { "こんにちは".bytesplice(3, 3, "こんにちは", 1, 0) }.should raise_error(IndexError, "offset 1 does not land on character boundary")
    end

    it "raises IndexError when str_length is not matching the codepoint boundary" do
      -> { "こんにちは".bytesplice(3, 3, "こんにちは", 0, 1) }.should raise_error(IndexError, "offset 1 does not land on character boundary")
      -> { "こんにちは".bytesplice(3, 3, "こんにちは", 0, 2) }.should raise_error(IndexError, "offset 2 does not land on character boundary")
    end

    it "replaces with integer str indices" do
      "こんにちは".bytesplice(3, 3, "こんにちは", -15, 0).should == "こにちは"
      "こんにちは".bytesplice(3, 3, "こんにちは", 0, 0).should == "こにちは"
      "こんにちは".bytesplice(3, 3, "こんにちは", 0, 3).should == "ここにちは"
      "こんにちは".bytesplice(3, 3, "はは", 3, 3).should == "こはにちは"
      "こんにちは".bytesplice(3, 3, "こんにちは", 15, 0).should == "こにちは"
    end

    it "replaces with str range" do
      "こんにちは".bytesplice(0..2, "こんにちは", -15...-16).should == "んにちは"
      "こんにちは".bytesplice(0..2, "こんにちは", 0...0).should == "んにちは"
      "こんにちは".bytesplice(0..2, "こんにちは", 3..5).should == "んんにちは"
      "こんにちは".bytesplice(0..2, "こんにちは", 3...6).should == "んんにちは"
      "こんにちは".bytesplice(0..2, "こんにちは", 3..8).should == "んにんにちは"
      "こんにちは".bytesplice(0..2, "こんにちは", 0..-1).should == "こんにちはんにちは"
      "こんにちは".bytesplice(0..2, "こんにちは", 0...15).should == "こんにちはんにちは"
      "こんにちは".bytesplice(0..2, "こんにちは", 0...18).should == "こんにちはんにちは"
    end

    it "treats negative length for str range as 0" do
      "こんにちは".bytesplice(0..2, "こんにちは", 0...-100).should == "んにちは"
      "こんにちは".bytesplice(0..2, "こんにちは", 3...-100).should == "んにちは"
      "こんにちは".bytesplice(0..2, "こんにちは", -15...-100).should == "んにちは"
    end

    it "raises when ranges not match codepoint boundaries in str" do
      -> { "こんにちは".bytesplice(3...3, "こ", 0..0) }.should raise_error(IndexError, "offset 1 does not land on character boundary")
      -> { "こんにちは".bytesplice(3...3, "こ", 0..1) }.should raise_error(IndexError, "offset 2 does not land on character boundary")
      # Begin is incorrect
      -> { "こんにちは".bytesplice(3...3, "こんにちは", -4..-1) }.should raise_error(IndexError, "offset 11 does not land on character boundary")
      -> { "こんにちは".bytesplice(3...3, "こんにちは", -5..-1) }.should raise_error(IndexError, "offset 10 does not land on character boundary")
      # End is incorrect
      -> { "こんにちは".bytesplice(3...3, "こんにちは", -3..-2) }.should raise_error(IndexError, "offset 14 does not land on character boundary")
      -> { "こんにちは".bytesplice(3...3, "こんにちは", -3..-3) }.should raise_error(IndexError, "offset 13 does not land on character boundary")
    end

    it "deals with a different encoded argument with str index/length" do
      s = "こんにちは"
      s.encoding.should == Encoding::UTF_8
      sub = "goodbye"
      sub.force_encoding(Encoding::US_ASCII)

      result = s.bytesplice(3, 3, sub, 0, 3)
      result.should == "こgooにちは"
      result.encoding.should == Encoding::UTF_8

      s = "hello"
      s.force_encoding(Encoding::US_ASCII)
      sub = "こんにちは"
      sub.encoding.should == Encoding::UTF_8

      result = s.bytesplice(1, 2, sub, 3, 3)
      result.should == "hんlo"
      result.encoding.should == Encoding::UTF_8
    end

    it "deals with a different encoded argument with str range" do
      s = "こんにちは"
      s.encoding.should == Encoding::UTF_8
      sub = "goodbye"
      sub.force_encoding(Encoding::US_ASCII)

      result = s.bytesplice(3..5, sub, 0..2)
      result.should == "こgooにちは"
      result.encoding.should == Encoding::UTF_8

      s = "hello"
      s.force_encoding(Encoding::US_ASCII)
      sub = "こんにちは"
      sub.encoding.should == Encoding::UTF_8

      result = s.bytesplice(1..2, sub, 3..5)
      result.should == "hんlo"
      result.encoding.should == Encoding::UTF_8
    end
  end
end
