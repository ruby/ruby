require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "StringIO#ungetc when passed [char]" do
  before :each do
    @io = StringIO.new(+'1234')
  end

  it "writes the passed char before the current position" do
    @io.pos = 1
    @io.ungetc(?A)
    @io.string.should == 'A234'
  end

  it "writes the passed string before the current position" do
    @io.pos = 3
    @io.ungetc("foo")
    @io.string.should == 'foo4'
  end

  it "writes the passed string at the start if the current position is 0" do
    @io.pos = 0
    @io.ungetc("A")
    @io.string.should == 'A1234'
  end

  it "returns nil" do
    @io.pos = 1
    @io.ungetc(?A).should == nil
  end

  it "decreases the current position by one" do
    @io.pos = 2
    @io.ungetc(?A)
    @io.pos.should.eql?(1)
  end

  it "decreases the current position by the size of a multibyte character" do
    @io.pos = 2
    @io.ungetc("φ")
    @io.pos.should == 0
    @io.string.should == "φ34"
  end

  it "writes the given string completely when the current position does not have enough space" do
    @io.pos = 2
    @io.ungetc("foo")
    @io.pos.should == 0
    @io.string.should == "foo34"
  end

  it "pads with \\000 when the current position is after the end" do
    @io.pos = 15
    @io.ungetc(?A)
    @io.string.should == "1234\000\000\000\000\000\000\000\000\000\000A"
    @io.pos.should == 14
  end

  it "pads with \\000 when the current position is after the end for a multibyte character" do
    @io.pos = 15
    @io.ungetc("φ")
    @io.string.should == "1234\000\000\000\000\000\000\000\000\000φ"
    @io.pos.should == 13
  end

  it "tries to convert the passed argument to an String using #to_str" do
    obj = mock("to_str")
    obj.should_receive(:to_str).and_return(?A)

    @io.pos = 1
    @io.ungetc(obj)
    @io.string.should == "A234"
  end

  it "raises a TypeError when the passed length can't be converted to an Integer or String" do
    -> { @io.ungetc(Object.new) }.should.raise(TypeError)
  end
end

describe "StringIO#ungetc when self is not readable" do
  it "raises an IOError" do
    io = StringIO.new(+"test", "w")
    io.pos = 1
    -> { io.ungetc(?A) }.should.raise(IOError)

    io = StringIO.new(+"test")
    io.pos = 1
    io.close_read
    -> { io.ungetc(?A) }.should.raise(IOError)
  end
end

# Note: This is incorrect.
#
# describe "StringIO#ungetc when self is not writable" do
#   it "raises an IOError" do
#     io = StringIO.new(+"test", "r")
#     io.pos = 1
#     lambda { io.ungetc(?A) }.should.raise(IOError)
#
#     io = StringIO.new(+"test")
#     io.pos = 1
#     io.close_write
#     lambda { io.ungetc(?A) }.should.raise(IOError)
#   end
# end
