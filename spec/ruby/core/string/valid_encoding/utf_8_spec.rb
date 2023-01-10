# -*- encoding: utf-8 -*-
require_relative '../../../spec_helper'

describe "String#valid_encoding? and UTF-8" do
  def utf8(bytes)
    bytes.pack("C*").force_encoding("UTF-8")
  end

  describe "1-byte character" do
    it "is valid if is in format 0xxxxxxx" do
      utf8([0b00000000]).valid_encoding?.should == true
      utf8([0b01111111]).valid_encoding?.should == true
    end

    it "is not valid if is not in format 0xxxxxxx" do
      utf8([0b10000000]).valid_encoding?.should == false
      utf8([0b11111111]).valid_encoding?.should == false
    end
  end

  describe "2-bytes character" do
    it "is valid if in format [110xxxxx 10xxxxx]" do
      utf8([0b11000010, 0b10000000]).valid_encoding?.should == true
      utf8([0b11000010, 0b10111111]).valid_encoding?.should == true

      utf8([0b11011111, 0b10000000]).valid_encoding?.should == true
      utf8([0b11011111, 0b10111111]).valid_encoding?.should == true
    end

    it "is not valid if the first byte is not in format 110xxxxx" do
      utf8([0b00000010, 0b10000000]).valid_encoding?.should == false
      utf8([0b00100010, 0b10000000]).valid_encoding?.should == false
      utf8([0b01000010, 0b10000000]).valid_encoding?.should == false
      utf8([0b01100010, 0b10000000]).valid_encoding?.should == false
      utf8([0b10000010, 0b10000000]).valid_encoding?.should == false
      utf8([0b10100010, 0b10000000]).valid_encoding?.should == false
      utf8([0b11000010, 0b10000000]).valid_encoding?.should == true # correct bytes
      utf8([0b11100010, 0b10000000]).valid_encoding?.should == false
    end

    it "is not valid if the second byte is not in format 10xxxxxx" do
      utf8([0b11000010, 0b00000000]).valid_encoding?.should == false
      utf8([0b11000010, 0b01000000]).valid_encoding?.should == false
      utf8([0b11000010, 0b11000000]).valid_encoding?.should == false
    end

    it "is not valid if is smaller than [xxxxxx10 xx000000] (codepoints < U+007F, that are encoded with the 1-byte format)" do
      utf8([0b11000000, 0b10111111]).valid_encoding?.should == false
      utf8([0b11000001, 0b10111111]).valid_encoding?.should == false
    end

    it "is not valid if the first byte is missing" do
      bytes = [0b11000010, 0b10000000]
      utf8(bytes[1..1]).valid_encoding?.should == false
    end

    it "is not valid if the second byte is missing" do
      bytes = [0b11000010, 0b10000000]
      utf8(bytes[0..0]).valid_encoding?.should == false
    end
  end

  describe "3-bytes character" do
    it "is valid if in format [1110xxxx 10xxxxxx 10xxxxxx]" do
      utf8([0b11100000, 0b10100000, 0b10000000]).valid_encoding?.should == true
      utf8([0b11100000, 0b10100000, 0b10111111]).valid_encoding?.should == true
      utf8([0b11100000, 0b10111111, 0b10111111]).valid_encoding?.should == true
      utf8([0b11101111, 0b10111111, 0b10111111]).valid_encoding?.should == true
    end

    it "is not valid if the first byte is not in format 1110xxxx" do
      utf8([0b00000000, 0b10100000, 0b10000000]).valid_encoding?.should == false
      utf8([0b00010000, 0b10100000, 0b10000000]).valid_encoding?.should == false
      utf8([0b00100000, 0b10100000, 0b10000000]).valid_encoding?.should == false
      utf8([0b00110000, 0b10100000, 0b10000000]).valid_encoding?.should == false
      utf8([0b01000000, 0b10100000, 0b10000000]).valid_encoding?.should == false
      utf8([0b01010000, 0b10100000, 0b10000000]).valid_encoding?.should == false
      utf8([0b01100000, 0b10100000, 0b10000000]).valid_encoding?.should == false
      utf8([0b01110000, 0b10100000, 0b10000000]).valid_encoding?.should == false
      utf8([0b10000000, 0b10100000, 0b10000000]).valid_encoding?.should == false
      utf8([0b10010000, 0b10100000, 0b10000000]).valid_encoding?.should == false
      utf8([0b10100000, 0b10100000, 0b10000000]).valid_encoding?.should == false
      utf8([0b10110000, 0b10100000, 0b10000000]).valid_encoding?.should == false
      utf8([0b11000000, 0b10100000, 0b10000000]).valid_encoding?.should == false
      utf8([0b11010000, 0b10100000, 0b10000000]).valid_encoding?.should == false
      utf8([0b11100000, 0b10100000, 0b10000000]).valid_encoding?.should == true # correct bytes
      utf8([0b11110000, 0b10100000, 0b10000000]).valid_encoding?.should == false
    end

    it "is not valid if the second byte is not in format 10xxxxxx" do
      utf8([0b11100000, 0b00100000, 0b10000000]).valid_encoding?.should == false
      utf8([0b11100000, 0b01100000, 0b10000000]).valid_encoding?.should == false
      utf8([0b11100000, 0b11100000, 0b10000000]).valid_encoding?.should == false
    end

    it "is not valid if the third byte is not in format 10xxxxxx" do
      utf8([0b11100000, 0b10100000, 0b00000000]).valid_encoding?.should == false
      utf8([0b11100000, 0b10100000, 0b01000000]).valid_encoding?.should == false
      utf8([0b11100000, 0b10100000, 0b01000000]).valid_encoding?.should == false
    end

    it "is not valid if is smaller than [xxxx0000 xx100000 xx000000] (codepoints < U+07FF that are encoded with the 2-byte format)" do
      utf8([0b11100000, 0b10010000, 0b10000000]).valid_encoding?.should == false
      utf8([0b11100000, 0b10001000, 0b10000000]).valid_encoding?.should == false
      utf8([0b11100000, 0b10000100, 0b10000000]).valid_encoding?.should == false
      utf8([0b11100000, 0b10000010, 0b10000000]).valid_encoding?.should == false
      utf8([0b11100000, 0b10000001, 0b10000000]).valid_encoding?.should == false
      utf8([0b11100000, 0b10000000, 0b10000000]).valid_encoding?.should == false
    end

    it "is not valid if in range [xxxx1101 xx100000 xx000000] - [xxxx1101 xx111111 xx111111] (codepoints U+D800 - U+DFFF)" do
      utf8([0b11101101, 0b10100000, 0b10000000]).valid_encoding?.should == false
      utf8([0b11101101, 0b10100000, 0b10000001]).valid_encoding?.should == false
      utf8([0b11101101, 0b10111111, 0b10111111]).valid_encoding?.should == false

      utf8([0b11101101, 0b10011111, 0b10111111]).valid_encoding?.should == true # lower boundary - 1
      utf8([0b11101110, 0b10000000, 0b10000000]).valid_encoding?.should == true # upper boundary + 1
    end

    it "is not valid if the first byte is missing" do
      bytes = [0b11100000, 0b10100000, 0b10000000]
      utf8(bytes[2..3]).valid_encoding?.should == false
    end

    it "is not valid if the second byte is missing" do
      bytes = [0b11100000, 0b10100000, 0b10000000]
      utf8([bytes[0], bytes[2]]).valid_encoding?.should == false
    end

    it "is not valid if the second and the third bytes are missing" do
      bytes = [0b11100000, 0b10100000, 0b10000000]
      utf8(bytes[0..0]).valid_encoding?.should == false
    end
  end

  describe "4-bytes character" do
    it "is valid if in format [11110xxx 10xxxxxx 10xxxxxx 10xxxxxx]" do
      utf8([0b11110000, 0b10010000, 0b10000000, 0b10000000]).valid_encoding?.should == true
      utf8([0b11110000, 0b10010000, 0b10000000, 0b10111111]).valid_encoding?.should == true
      utf8([0b11110000, 0b10010000, 0b10111111, 0b10111111]).valid_encoding?.should == true
      utf8([0b11110000, 0b10111111, 0b10111111, 0b10111111]).valid_encoding?.should == true
      utf8([0b11110100, 0b10001111, 0b10111111, 0b10111111]).valid_encoding?.should == true
    end

    it "is not valid if the first byte is not in format 11110xxx" do
      utf8([0b11100000, 0b10010000, 0b10000000, 0b10000000]).valid_encoding?.should == false
      utf8([0b11010000, 0b10010000, 0b10000000, 0b10000000]).valid_encoding?.should == false
      utf8([0b10110000, 0b10010000, 0b10000000, 0b10000000]).valid_encoding?.should == false
      utf8([0b01110000, 0b10010000, 0b10000000, 0b10000000]).valid_encoding?.should == false
    end

    it "is not valid if the second byte is not in format 10xxxxxx" do
      utf8([0b11110000, 0b00010000, 0b10000000, 0b10000000]).valid_encoding?.should == false
      utf8([0b11110000, 0b01010000, 0b10000000, 0b10000000]).valid_encoding?.should == false
      utf8([0b11110000, 0b10010000, 0b10000000, 0b10000000]).valid_encoding?.should == true # correct bytes
      utf8([0b11110000, 0b11010000, 0b10000000, 0b10000000]).valid_encoding?.should == false
    end

    it "is not valid if the third byte is not in format 10xxxxxx" do
      utf8([0b11110000, 0b10010000, 0b00000000, 0b10000000]).valid_encoding?.should == false
      utf8([0b11110000, 0b10010000, 0b01000000, 0b10000000]).valid_encoding?.should == false
      utf8([0b11110000, 0b10010000, 0b10000000, 0b10000000]).valid_encoding?.should == true # correct bytes
      utf8([0b11110000, 0b10010000, 0b11000000, 0b10000000]).valid_encoding?.should == false
    end

    it "is not valid if the forth byte is not in format 10xxxxxx" do
      utf8([0b11110000, 0b10010000, 0b10000000, 0b00000000]).valid_encoding?.should == false
      utf8([0b11110000, 0b10010000, 0b10000000, 0b01000000]).valid_encoding?.should == false
      utf8([0b11110000, 0b10010000, 0b10000000, 0b10000000]).valid_encoding?.should == true # correct bytes
      utf8([0b11110000, 0b10010000, 0b10000000, 0b11000000]).valid_encoding?.should == false
    end

    it "is not valid if is smaller than [xxxxx000 xx001000 xx000000 xx000000] (codepoint < U+10000)" do
      utf8([0b11110000, 0b10000111, 0b10000000, 0b10000000]).valid_encoding?.should == false
      utf8([0b11110000, 0b10000110, 0b10000000, 0b10000000]).valid_encoding?.should == false
      utf8([0b11110000, 0b10000101, 0b10000000, 0b10000000]).valid_encoding?.should == false
      utf8([0b11110000, 0b10000100, 0b10000000, 0b10000000]).valid_encoding?.should == false
      utf8([0b11110000, 0b10000011, 0b10000000, 0b10000000]).valid_encoding?.should == false
      utf8([0b11110000, 0b10000010, 0b10000000, 0b10000000]).valid_encoding?.should == false
      utf8([0b11110000, 0b10000001, 0b10000000, 0b10000000]).valid_encoding?.should == false
      utf8([0b11110000, 0b10000000, 0b10000000, 0b10000000]).valid_encoding?.should == false
    end

    it "is not valid if is greater than [xxxxx100 xx001111 xx111111 xx111111] (codepoint > U+10FFFF)" do
      utf8([0b11110100, 0b10010000, 0b10000000, 0b10000000]).valid_encoding?.should == false
      utf8([0b11110100, 0b10100000, 0b10000000, 0b10000000]).valid_encoding?.should == false
      utf8([0b11110100, 0b10110000, 0b10000000, 0b10000000]).valid_encoding?.should == false

      utf8([0b11110101, 0b10001111, 0b10111111, 0b10111111]).valid_encoding?.should == false
      utf8([0b11110110, 0b10001111, 0b10111111, 0b10111111]).valid_encoding?.should == false
      utf8([0b11110111, 0b10001111, 0b10111111, 0b10111111]).valid_encoding?.should == false
    end

    it "is not valid if the first byte is missing" do
      bytes = [0b11110000, 0b10010000, 0b10000000, 0b10000000]
      utf8(bytes[1..3]).valid_encoding?.should == false
    end

    it "is not valid if the second byte is missing" do
      bytes = [0b11110000, 0b10010000, 0b10000000, 0b10000000]
      utf8([bytes[0], bytes[2], bytes[3]]).valid_encoding?.should == false
    end

    it "is not valid if the second and the third bytes are missing" do
      bytes = [0b11110000, 0b10010000, 0b10000000, 0b10000000]
      utf8([bytes[0], bytes[3]]).valid_encoding?.should == false
    end

    it "is not valid if the second, the third and the fourth bytes are missing" do
      bytes = [0b11110000, 0b10010000, 0b10000000, 0b10000000]
      utf8(bytes[0..0]).valid_encoding?.should == false
    end
  end
end
