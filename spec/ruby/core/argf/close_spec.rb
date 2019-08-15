require_relative '../../spec_helper'

describe "ARGF.close" do
  before :each do
    @file1_name = fixture __FILE__, "file1.txt"
    @file2_name = fixture __FILE__, "file2.txt"
  end

  it "closes the current open stream" do
    argf [@file1_name, @file2_name] do
      io = @argf.to_io
      @argf.close
      io.closed?.should be_true
    end
  end

  it "returns self" do
    argf [@file1_name, @file2_name] do
      @argf.close.should equal(@argf)
    end
  end

  it "doesn't raise an IOError if called on a closed stream" do
    argf [@file1_name] do
      -> { @argf.close }.should_not raise_error
      -> { @argf.close }.should_not raise_error
    end
  end
end

describe "ARGF.close" do
  it "does not close STDIN" do
    ruby_exe("ARGV.replace(['-']); ARGF.close; print ARGF.closed?").should == "false"
  end
end
