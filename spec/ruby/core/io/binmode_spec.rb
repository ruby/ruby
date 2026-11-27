require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "IO#binmode" do
  before :each do
    @name = tmp("io_binmode.txt")
  end

  after :each do
    @io.close if @io and !@io.closed?
    rm_r @name
  end

  it "returns self" do
    @io = new_io(@name)
    @io.binmode.should.equal?(@io)
  end

  it "raises an IOError on closed stream" do
    -> { IOSpecs.closed_io.binmode }.should.raise(IOError)
  end

  it "sets external encoding to binary" do
    @io = new_io(@name, "w:utf-8")
    @io.binmode
    @io.external_encoding.should == Encoding::BINARY
  end

  it "sets internal encoding to nil" do
    @io = new_io(@name, "w:utf-8:ISO-8859-1")
    @io.binmode
    @io.internal_encoding.should == nil
  end

  it "disables newline conversion for #read" do
    data = "line1\r\nline2\r\n"

    @io = new_io(@name, "wb")
    @io.write(data)
    @io.close

    @io = new_io(@name, "rt")
    @io.set_encoding("utf-8:ISO-8859-1", newline: :universal)
    @io.binmode
    @io.read.should == data
  end

  it "disables newline conversion for #gets" do
    data = "line1\r\nline2\r\n"

    @io = new_io(@name, "wb")
    @io.write(data)
    @io.close

    @io = new_io(@name, "rt")
    @io.set_encoding("utf-8:ISO-8859-1", newline: :universal)
    @io.binmode
    @io.gets.should == "line1\r\n"
    @io.gets.should == "line2\r\n"
  end

  it "disables newline conversion for #readline" do
    data = "line1\r\nline2\r\n"

    @io = new_io(@name, "wb")
    @io.write(data)
    @io.close

    @io = new_io(@name, "rt")
    @io.set_encoding("utf-8:ISO-8859-1", newline: :universal)
    @io.binmode
    @io.readline.should == "line1\r\n"
    @io.readline.should == "line2\r\n"
  end

  it "disables newline conversion for #readlines" do
    data = "line1\r\nline2\r\n"

    @io = new_io(@name, "wb")
    @io.write(data)
    @io.close

    @io = new_io(@name, "rt")
    @io.set_encoding("utf-8:ISO-8859-1", newline: :universal)
    @io.binmode
    @io.readlines.should == ["line1\r\n", "line2\r\n"]
  end

  it "disables newline conversion for #each" do
    data = "line1\r\nline2\r\n"

    @io = new_io(@name, "wb")
    @io.write(data)
    @io.close

    @io = new_io(@name, "rt")
    @io.set_encoding("utf-8:ISO-8859-1", newline: :universal)
    @io.binmode
    @io.each.to_a.should == ["line1\r\n", "line2\r\n"]
  end

  it "disables newline conversion for #each_line" do
    data = "line1\r\nline2\r\n"

    @io = new_io(@name, "wb")
    @io.write(data)
    @io.close

    @io = new_io(@name, "rt")
    @io.set_encoding("utf-8:ISO-8859-1", newline: :universal)
    @io.binmode
    @io.each_line.to_a.should == ["line1\r\n", "line2\r\n"]
  end

  it "disables newline conversion for #getc" do
    data = "line1\r\n"

    @io = new_io(@name, "wb")
    @io.write(data)
    @io.close

    @io = new_io(@name, "rt")
    @io.set_encoding("utf-8:ISO-8859-1", newline: :universal)
    @io.binmode
    5.times { @io.getc }
    @io.getc.should == "\r"
    @io.getc.should == "\n"
  end

  it "disables newline conversion for #readchar" do
    data = "line1\r\n"

    @io = new_io(@name, "wb")
    @io.write(data)
    @io.close

    @io = new_io(@name, "rt")
    @io.set_encoding("utf-8:ISO-8859-1", newline: :universal)
    @io.binmode
    5.times { @io.readchar }
    @io.readchar.should == "\r"
    @io.readchar.should == "\n"
  end

  it "disables newline conversion for #each_char" do
    data = "line1\r\n"

    @io = new_io(@name, "wb")
    @io.write(data)
    @io.close

    @io = new_io(@name, "rt")
    @io.set_encoding("utf-8:ISO-8859-1", newline: :universal)
    @io.binmode
    @io.each_char.to_a.should == ["l", "i", "n", "e", "1", "\r", "\n"]
  end

  it "disables newline conversion for #each_codepoint" do
    data = "line1\r\n"

    @io = new_io(@name, "wb")
    @io.write(data)
    @io.close

    @io = new_io(@name, "rt")
    @io.set_encoding("utf-8:ISO-8859-1", newline: :universal)
    @io.binmode
    @io.each_codepoint.to_a.should == [108, 105, 110, 101, 49, 13, 10]
  end
end

describe "IO#binmode?" do
  before :each do
    @filename = tmp("IO_binmode_file")
    @file = File.open(@filename, "w")
    @duped = nil
  end

  after :each do
    @duped.close if @duped
    @file.close
    rm_r @filename
  end

  it "is true after a call to IO#binmode" do
    @file.binmode?.should == false
    @file.binmode
    @file.binmode?.should == true
  end

  it "propagates to dup'ed IO objects" do
    @file.binmode
    @duped = @file.dup
    @duped.binmode?.should == @file.binmode?
  end

  it "raises an IOError on closed stream" do
    -> { IOSpecs.closed_io.binmode? }.should.raise(IOError)
  end
end
