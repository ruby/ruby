# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "IO#rewind" do
  before :each do
    @io = IOSpecs.io_fixture "lines.txt"
  end

  after :each do
    @io.close unless @io.closed?
  end

  it "positions the instance to the beginning of input" do
    @io.readline.should == "Voici la ligne une.\n"
    @io.readline.should == "Qui è la linea due.\n"
    @io.rewind
    @io.readline.should == "Voici la ligne une.\n"
  end

  it "positions the instance to the beginning of output for write-only IO" do
    name = tmp("io_rewind_spec")
    io = File.open(name, "w")
    io.write("Voici la ligne une.\n")
    io.rewind
    io.pos.should == 0
  ensure
    io.close
    rm_r name
  end

  it "positions the instance to the beginning of input and clears EOF" do
    value = @io.read
    @io.rewind
    @io.should_not.eof?
    value.should == @io.read
  end

  it "sets lineno to 0" do
    @io.readline.should == "Voici la ligne une.\n"
    @io.lineno.should == 1
    @io.rewind
    @io.lineno.should == 0
  end

  it "returns 0" do
    @io.rewind.should == 0
  end

  it "raises IOError on closed stream" do
    -> { IOSpecs.closed_io.rewind }.should raise_error(IOError)
  end
end
