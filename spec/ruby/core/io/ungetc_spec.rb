# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "IO#ungetc" do
  before :each do
    @io = IOSpecs.io_fixture "lines.txt"

    @empty = tmp('empty.txt')
  end

  after :each do
    @io.close unless @io.closed?
    rm_r @empty
  end

  it "pushes back one character onto stream" do
    @io.getc.should == ?V
    @io.ungetc(86)
    @io.getc.should == ?V

    @io.ungetc(10)
    @io.getc.should == ?\n

    @io.getc.should == ?o
    @io.getc.should == ?i
    # read the rest of line
    @io.readline.should == "ci la ligne une.\n"
    @io.getc.should == ?Q
    @io.ungetc(99)
    @io.getc.should == ?c
  end

  it "interprets the codepoint in the external encoding" do
    @io.set_encoding(Encoding::UTF_8)
    @io.ungetc(233)
    c = @io.getc
    c.encoding.should == Encoding::UTF_8
    c.should == "é"
    c.bytes.should == [195, 169]

    @io.set_encoding(Encoding::IBM437)
    @io.ungetc(130)
    c = @io.getc
    c.encoding.should == Encoding::IBM437
    c.bytes.should == [130]
    c.encode(Encoding::UTF_8).should == "é"
  end

  it "pushes back one character when invoked at the end of the stream" do
    # read entire content
    @io.read
    @io.ungetc(100)
    @io.getc.should == ?d
  end

  it "pushes back one character when invoked at the start of the stream" do
    @io.read(0)
    @io.ungetc(100)
    @io.getc.should == ?d
  end

  it "pushes back one character when invoked on empty stream" do
    touch(@empty)

    File.open(@empty) { |empty|
      empty.getc().should == nil
      empty.ungetc(10)
      empty.getc.should == ?\n
    }
  end

  it "affects EOF state" do
    touch(@empty)

    File.open(@empty) { |empty|
      empty.eof?.should == true
      empty.getc.should == nil
      empty.ungetc(100)
      empty.eof?.should == false
    }
  end

  it "adjusts the stream position" do
    @io.pos.should == 0

    # read one char
    c = @io.getc
    @io.pos.should == 1
    @io.ungetc(c)
    @io.pos.should == 0

    # read all
    @io.read
    pos = @io.pos
    @io.ungetc(98)
    @io.pos.should == pos - 1
  end

  it "makes subsequent unbuffered operations to raise IOError" do
    @io.getc
    @io.ungetc(100)
    -> { @io.sysread(1) }.should raise_error(IOError)
  end

  it "does not affect the stream and returns nil when passed nil" do
    @io.getc.should == ?V
    @io.ungetc(nil)
    @io.getc.should == ?o
  end

  it "puts one or more characters back in the stream" do
    @io.gets
    @io.ungetc("Aquí ").should be_nil
    @io.gets.chomp.should == "Aquí Qui è la linea due."
  end

  it "calls #to_str to convert the argument if it is not an Integer" do
    chars = mock("io ungetc")
    chars.should_receive(:to_str).and_return("Aquí ")

    @io.ungetc(chars).should be_nil
    @io.gets.chomp.should == "Aquí Voici la ligne une."
  end

  it "returns nil when invoked on stream that was not yet read" do
    @io.ungetc(100).should be_nil
  end

  it "raises IOError on closed stream" do
    @io.getc
    @io.close
    -> { @io.ungetc(100) }.should raise_error(IOError)
  end
end
