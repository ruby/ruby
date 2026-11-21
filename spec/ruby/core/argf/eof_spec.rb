require_relative '../../spec_helper'

describe "ARGF.eof" do
  it "is an alias of ARGF.eof?" do
    ARGF.method(:eof).should == ARGF.method(:eof?)
  end
end

describe "ARGF.eof?" do
  before :each do
    @file1 = fixture __FILE__, "file1.txt"
    @file2 = fixture __FILE__, "file2.txt"
  end

  # NOTE: this test assumes that fixtures files have two lines each
  it "returns true when reaching the end of a file" do
    argf [@file1, @file2] do
      result = []
      while @argf.gets
        result << @argf.eof?
      end
      result.should == [false, true, false, true]
    end
  end

  it "raises IOError when called on a closed stream" do
    argf [@file1] do
      @argf.read
      -> { @argf.eof? }.should.raise(IOError)
    end
  end
end
