require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "ARGF.readlines" do
  before :each do
    @file1 = fixture __FILE__, "file1.txt"
    @file2 = fixture __FILE__, "file2.txt"

    @lines  = File.readlines(@file1)
    @lines += File.readlines(@file2)
  end

  it "reads all lines of all files" do
    argf [@file1, @file2] do
      @argf.readlines.should == @lines
    end
  end

  it "reads all lines of all files without the trailing separator when passed chomp" do
    argf [@file1, @file2] do
      @argf.readlines(chomp: true).should == @lines.map(&:chomp)
    end
  end

  it "reads all limited sections of all files when passed a separator and a limit" do
    argf [@file1, @file2] do
      @argf.readlines(".", 4).should ==
        (File.readlines(@file1, ".", 4) + File.readlines(@file2, ".", 4))
    end
  end

  describe "when reading $stdin and $stdin is not an IO" do
    before :each do
      @stdin = $stdin
      $stdin = ARGFSpecs::Stdin.new("a\nb\n")
      @stdin_argf = ARGF.class.new
    end

    after :each do
      $stdin = @stdin
    end

    it "calls readlines on $stdin" do
      @stdin_argf.readlines.should == ["a\n", "b\n"]
      $stdin.calls.should == [[:readlines, [], {}]]
    end

    it "passes the separator, limit and keywords to $stdin.readlines" do
      @stdin_argf.readlines("\n", 1, chomp: true).should == ["a", "", "b", ""]
      $stdin.calls.should == [[:readlines, ["\n", 1], { chomp: true }]]
    end
  end

  it "returns an empty Array when end of stream reached" do
    argf [@file1, @file2] do
      @argf.read
      @argf.readlines.should == []
    end
  end
end

describe "ARGF.readlines when reading $stdin and $stdin is not an IO" do
  before :each do
    @stdin = $stdin
  end

  after :each do
    $stdin = @stdin
  end

  it "raises NoMethodError when $stdin has no public readlines" do
    $stdin = Object.new
    -> { ARGF.class.new.readlines }.should.raise(NoMethodError)
  end
end
