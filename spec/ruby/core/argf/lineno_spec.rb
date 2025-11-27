require_relative '../../spec_helper'

describe "ARGF.lineno" do
  before :each do
    @file1 = fixture __FILE__, "file1.txt"
    @file2 = fixture __FILE__, "file2.txt"
  end

  # NOTE: these examples assume that the fixture files have two lines each
  it "starts counting from 1 after resetting the line number" do
    argf [@file1, @file2] do
      @argf.lineno = 0
      @argf.gets
      @argf.lineno.should == 1
    end
  end

  it "increments with each additional line in the current file" do
    argf [@file1] do
      @argf.lineno = 0
      @argf.gets
      @argf.gets
      @argf.lineno.should == 2
    end
  end

  it "continues counting when moving to the next file" do
    argf [@file1, @file2] do
      @argf.lineno = 0
      3.times { @argf.gets }
      @argf.lineno.should == 3

      @argf.gets
      @argf.lineno.should == 4
    end
  end

  it "returns the total line number once all input has been read" do
    argf [@file1, @file2] do
      @argf.lineno = 0
      @argf.each_line { }
      @argf.lineno.should == 4
    end
  end

  it "aliases to $." do
    script = fixture __FILE__, "lineno.rb"
    out = ruby_exe(script, args: [@file1, @file2])
    out.should == "0\n1\n2\n"
  end
end
