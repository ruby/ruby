require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "ARGF.each_line" do
  before :each do
    @file1_name = fixture __FILE__, "file1.txt"
    @file2_name = fixture __FILE__, "file2.txt"

    @lines  = File.readlines @file1_name
    @lines += File.readlines @file2_name
  end

  it "is a public method" do
    argf [@file1_name, @file2_name] do
      @argf.public_methods(false).should.include?(:each_line)
    end
  end

  it "requires multiple arguments" do
    argf [@file1_name, @file2_name] do
      @argf.method(:each_line).arity.should < 0
    end
  end

  it "reads each line of files" do
    argf [@file1_name, @file2_name] do
      lines = []
      @argf.each_line { |b| lines << b }
      lines.should == @lines
    end
  end

  it "returns self when passed a block" do
    argf [@file1_name, @file2_name] do
      @argf.each_line {}.should.equal?(@argf)
    end
  end

  describe "with a separator" do
    it "yields each separated section of all streams" do
      argf [@file1_name, @file2_name] do
        @argf.each_line('.').to_a.should ==
          (File.readlines(@file1_name, '.') + File.readlines(@file2_name, '.'))
      end
    end
  end

  describe "with a separator and a limit" do
    it "yields each limited section of all streams" do
      argf [@file1_name, @file2_name] do
        lines = []
        @argf.each_line('.', 4) { |s| lines << s }
        lines.should == (File.readlines(@file1_name, '.', 4) + File.readlines(@file2_name, '.', 4))
      end
    end
  end

  describe "when passed chomp" do
    it "yields each line without the trailing separator" do
      argf [@file1_name, @file2_name] do
        lines = []
        @argf.each_line(chomp: true) { |s| lines << s }
        lines.should == @lines.map(&:chomp)
      end
    end

    it "yields each separated section without the separator when also passed a separator and a limit" do
      argf [@file1_name, @file2_name] do
        lines = []
        @argf.each_line('.', 8, chomp: true) { |s| lines << s }
        lines.should == (File.readlines(@file1_name, '.', 8, chomp: true) + File.readlines(@file2_name, '.', 8, chomp: true))
      end
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

    it "calls each_line on $stdin and yields each line" do
      lines = []
      @stdin_argf.each_line { |s| lines << s }
      lines.should == ["a\n", "b\n"]
      $stdin.calls.should == [[:each_line, [], {}]]
    end

    it "passes the separator, limit and keywords to $stdin.each_line" do
      lines = []
      @stdin_argf.each_line("\n", 1, chomp: true) { |s| lines << s }
      lines.should == ["a", "", "b", ""]
      $stdin.calls.should == [[:each_line, ["\n", 1], { chomp: true }]]
    end
  end

  describe "when no block is given" do
    it "returns an Enumerator" do
      argf [@file1_name, @file2_name] do
        @argf.each_line.should.instance_of?(Enumerator)
      end
    end

    it "returns an Enumerator that passes chomp to the method" do
      argf [@file1_name, @file2_name] do
        @argf.each_line(chomp: true).to_a.should == @lines.map(&:chomp)
      end
    end

    it "returns an Enumerator that passes the separator, limit and chomp to the method" do
      argf [@file1_name, @file2_name] do
        @argf.each_line('.', 8, chomp: true).to_a.should ==
          (File.readlines(@file1_name, '.', 8, chomp: true) + File.readlines(@file2_name, '.', 8, chomp: true))
      end
    end

    describe "returned Enumerator" do
      describe "size" do
        it "should return nil" do
          argf [@file1_name, @file2_name] do
            @argf.each_line.size.should == nil
          end
        end
      end
    end
  end
end
