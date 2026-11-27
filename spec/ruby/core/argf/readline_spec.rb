require_relative '../../spec_helper'
require_relative 'shared/gets'

describe "ARGF.readline" do
  it_behaves_like :argf_gets, :readline
end

describe "ARGF.readline" do
  it_behaves_like :argf_gets_inplace_edit, :readline
end

describe "ARGF.readline" do
  before :each do
    @file1 = fixture __FILE__, "file1.txt"
    @file2 = fixture __FILE__, "file2.txt"
  end

  it "raises an EOFError when reaching end of files" do
    argf [@file1, @file2] do
      -> { while @argf.readline; end }.should.raise(EOFError)
    end
  end
end

describe "ARGF.readline when reading $stdin and $stdin is not an IO" do
  before :each do
    @stdin = $stdin
  end

  after :each do
    $stdin = @stdin
  end

  it "calls readline on $stdin" do
    $stdin = mock("stdin")
    $stdin.should_receive(:readline).with("\n", 1, chomp: true).and_return("line")
    ARGF.class.new.readline("\n", 1, chomp: true).should == "line"
  end

  it "raises an EOFError when reaching end of $stdin" do
    $stdin = StringIO.new("a\n")
    argf = ARGF.class.new
    argf.readline.should == "a\n"
    -> { argf.readline }.should.raise(EOFError)
  end

  it "raises NoMethodError when $stdin has no public readline" do
    stdin = Object.new
    def stdin.gets(*) = "line\n"
    $stdin = stdin
    -> { ARGF.class.new.readline }.should.raise(NoMethodError)
  end
end
