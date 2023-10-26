# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "String#scrub with a default replacement" do
  it "returns self for valid strings" do
    input = "foo"

    input.scrub.should == input
  end

  it "replaces invalid byte sequences" do
    x81 = [0x81].pack('C').force_encoding('utf-8')
    "abc\u3042#{x81}".scrub.should == "abc\u3042\uFFFD"
  end

  it "replaces invalid byte sequences in lazy substrings" do
    x81 = [0x81].pack('C').force_encoding('utf-8')
    "abc\u3042#{x81}def"[1...-1].scrub.should == "bc\u3042\uFFFDde"
  end

  it "returns a copy of self when the input encoding is BINARY" do
    input = "foo".encode('BINARY')

    input.scrub.should == "foo"
  end

  it "replaces invalid byte sequences when using ASCII as the input encoding" do
    xE3x80 = [0xE3, 0x80].pack('CC').force_encoding 'utf-8'
    input = "abc\u3042#{xE3x80}".force_encoding('ASCII')
    input.scrub.should == "abc?????"
  end

  it "returns a String in the same encoding as self" do
    x81 = [0x81].pack('C').force_encoding('utf-8')
    "abc\u3042#{x81}".scrub.encoding.should == Encoding::UTF_8
  end

  it "returns String instances when called on a subclass" do
    StringSpecs::MyString.new("foo").scrub.should be_an_instance_of(String)
    input = [0x81].pack('C').force_encoding('utf-8')
    StringSpecs::MyString.new(input).scrub.should be_an_instance_of(String)
  end
end

describe "String#scrub with a custom replacement" do
  it "returns self for valid strings" do
    input = "foo"

    input.scrub("*").should == input
  end

  it "replaces invalid byte sequences" do
    x81 = [0x81].pack('C').force_encoding('utf-8')
    "abc\u3042#{x81}".scrub("*").should == "abc\u3042*"
  end

  it "replaces invalid byte sequences in frozen strings" do
    x81 = [0x81].pack('C').force_encoding('utf-8')
    (-"abc\u3042#{x81}").scrub("*").should == "abc\u3042*"

    leading_surrogate = [0x00, 0xD8]
    utf16_str = ("abc".encode('UTF-16LE').bytes + leading_surrogate).pack('c*').force_encoding('UTF-16LE')
    (-(utf16_str)).scrub("*".encode('UTF-16LE')).should == "abc*".encode('UTF-16LE')
  end

  it "replaces an incomplete character at the end with a single replacement" do
    xE3x80 = [0xE3, 0x80].pack('CC').force_encoding 'utf-8'
    xE3x80.scrub("*").should == "*"
  end

  it "raises ArgumentError for replacements with an invalid encoding" do
    x81 = [0x81].pack('C').force_encoding('utf-8')
    xE4 = [0xE4].pack('C').force_encoding('utf-8')
    block = -> { "foo#{x81}".scrub(xE4) }

    block.should raise_error(ArgumentError)
  end

  it "returns a String in the same encoding as self" do
    x81 = [0x81].pack('C').force_encoding('utf-8')
    "abc\u3042#{x81}".scrub("*").encoding.should == Encoding::UTF_8
  end

  it "raises TypeError when a non String replacement is given" do
    x81 = [0x81].pack('C').force_encoding('utf-8')
    block = -> { "foo#{x81}".scrub(1) }

    block.should raise_error(TypeError)
  end

  it "returns String instances when called on a subclass" do
    StringSpecs::MyString.new("foo").scrub("*").should be_an_instance_of(String)
    input = [0x81].pack('C').force_encoding('utf-8')
    StringSpecs::MyString.new(input).scrub("*").should be_an_instance_of(String)
  end
end

describe "String#scrub with a block" do
  it "returns self for valid strings" do
    input = "foo"

    input.scrub { |b| "*" }.should == input
  end

  it "replaces invalid byte sequences" do
    xE3x80 = [0xE3, 0x80].pack('CC').force_encoding 'utf-8'
    replaced = "abc\u3042#{xE3x80}".scrub { |b| "<#{b.unpack("H*")[0]}>" }

    replaced.should == "abc\u3042<e380>"
  end

  it "replaces invalid byte sequences using a custom encoding" do
    x80x80 = [0x80, 0x80].pack('CC').force_encoding 'utf-8'
    replaced = x80x80.scrub do |bad|
      bad.encode(Encoding::UTF_8, Encoding::Windows_1252)
    end

    replaced.should == "€€"
  end

  it "returns String instances when called on a subclass" do
    StringSpecs::MyString.new("foo").scrub { |b| "*" }.should be_an_instance_of(String)
    input = [0x81].pack('C').force_encoding('utf-8')
    StringSpecs::MyString.new(input).scrub { |b| "<#{b.unpack("H*")[0]}>" }.should be_an_instance_of(String)
  end
end

describe "String#scrub!" do
  it "modifies self for valid strings" do
    x81 = [0x81].pack('C').force_encoding('utf-8')
    input = "a#{x81}"
    input.scrub!
    input.should == "a\uFFFD"
  end

  it "accepts blocks" do
    x81 = [0x81].pack('C').force_encoding('utf-8')
    input = "a#{x81}"
    input.scrub! { |b| "<?>" }
    input.should == "a<?>"
  end

  it "maintains the state of frozen strings that are already valid" do
    input = "a"
    input.freeze
    input.scrub!
    input.frozen?.should be_true
  end

  it "preserves the instance variables of already valid strings" do
    input = "a"
    input.instance_variable_set(:@a, 'b')
    input.scrub!
    input.instance_variable_get(:@a).should == 'b'
  end

  it "accepts a frozen string as a replacement" do
    input = "a\xE2"
    input.scrub!('.'.freeze)
    input.should == 'a.'
  end
end
