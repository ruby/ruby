require_relative '../../spec_helper'

describe "ARGF.pos" do
  before :each do
    @file1 = fixture __FILE__, "file1.txt"
    @file2 = fixture __FILE__, "file2.txt"
  end

  it "gives the correct position for each read operation" do
    argf [@file1, @file2] do
      size1 = File.size(@file1)
      size2 = File.size(@file2)

      @argf.read(2)
      @argf.pos.should == 2
      @argf.read(size1-2)
      @argf.pos.should == size1
      @argf.read(6)
      @argf.pos.should == 6
      @argf.rewind
      @argf.pos.should == 0
      @argf.read(size2)
      @argf.pos.should == size2
    end
  end

  it "raises an ArgumentError when called on a closed stream" do
    argf [@file1] do
      @argf.read
      -> { @argf.pos }.should.raise(ArgumentError)
    end
  end
end

describe "ARGF.pos=" do
  before :each do
    @file1_name = fixture __FILE__, "file1.txt"
    @file2_name = fixture __FILE__, "file2.txt"

    @file1 = File.readlines @file1_name
    @file2 = File.readlines @file2_name
  end

  # NOTE: this test assumes that fixtures files have two lines each
  it "sets the correct position in files" do
    argf [@file1_name, @file2_name] do
      @argf.pos = @file1.first.size
      @argf.gets.should == @file1.last
      @argf.pos = 0
      @argf.gets.should == @file1.first

      # finish reading file1
      @argf.gets

      @argf.gets
      @argf.pos = 1
      @argf.gets.should == @file2.first[1..-1]

      @argf.pos = @file2.first.size + @file2.last.size - 1
      @argf.gets.should == @file2.last[-1,1]
      @argf.pos = 1000
      @argf.read.should == ""
    end
  end
end
