# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "IO#readline" do
  before :each do
    @io = IOSpecs.io_fixture "lines.txt"
  end

  after :each do
    @io.close unless @io.closed?
  end

  it "returns the next line on the stream" do
    @io.readline.should == "Voici la ligne une.\n"
    @io.readline.should == "Qui è la linea due.\n"
  end

  it "goes back to first position after a rewind" do
    @io.readline.should == "Voici la ligne une.\n"
    @io.rewind
    @io.readline.should == "Voici la ligne une.\n"
  end

  it "returns characters after the position set by #seek" do
    @io.seek(1)
    @io.readline.should == "oici la ligne une.\n"
  end

  it "raises EOFError on end of stream" do
    IOSpecs.lines.length.times { @io.readline }
    -> { @io.readline }.should raise_error(EOFError)
  end

  it "raises IOError on closed stream" do
    -> { IOSpecs.closed_io.readline }.should raise_error(IOError)
  end

  it "assigns the returned line to $_" do
    IOSpecs.lines.each do |line|
      @io.readline
      $_.should == line
    end
  end

  describe "when passed limit" do
    it "reads limit bytes" do
      @io.readline(3).should == "Voi"
    end

    it "returns an empty string when passed 0 as a limit" do
      @io.readline(0).should == ""
    end

    it "does not accept Integers that don't fit in a C off_t" do
      -> { @io.readline(2**128) }.should raise_error(RangeError)
    end
  end

  describe "when passed separator and limit" do
    it "reads limit bytes till the separator" do
      # Voici la ligne une.\
      @io.readline(" ", 4).should == "Voic"
      @io.readline(" ", 4).should == "i "
      @io.readline(" ", 4).should == "la "
      @io.readline(" ", 4).should == "lign"
      @io.readline(" ", 4).should == "e "
    end
  end

  describe "when passed chomp" do
    it "returns the first line without a trailing newline character" do
      @io.readline(chomp: true).should == IOSpecs.lines_without_newline_characters[0]
    end

    ruby_version_is "3.0" do
      it "raises exception when options passed as Hash" do
        -> { @io.readline({ chomp: true }) }.should raise_error(TypeError)

        -> {
          @io.readline("\n", 1, { chomp: true })
        }.should raise_error(ArgumentError, "wrong number of arguments (given 3, expected 0..2)")
      end
    end
  end
end
