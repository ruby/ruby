require_relative '../../spec_helper'
require_relative 'fixtures/classes'

# See redmine #1667
describe "IO#each_codepoint" do
  before :each do
    @io = IOSpecs.io_fixture "lines.txt"
    @enum = @io.each_codepoint
  end

  after :each do
    @io.close
  end

  describe "when no block is given" do
    it "returns an Enumerator" do
      @enum.should.instance_of?(Enumerator)
    end

    describe "returned Enumerator" do
      describe "size" do
        it "should return nil" do
          @enum.size.should == nil
        end
      end
    end
  end

  it "yields each codepoint" do
    @enum.first(25).should == [
      86, 111, 105, 99, 105, 32, 108, 97, 32, 108, 105, 103, 110,
      101, 32, 117, 110, 101, 46, 10, 81, 117, 105, 32, 232
    ]
  end

  it "yields each codepoint starting from the current position" do
    @io.pos = 130
    @enum.to_a.should == [101, 32, 115, 105, 120, 46, 10]
  end

  it "raises an error if reading invalid sequence" do
    @io.pos = 60  # inside of a multibyte sequence
    -> { @enum.first }.should.raise(ArgumentError)
  end

  it "does not change $_" do
    $_ = "test"
    @enum.to_a
    $_.should == "test"
  end

  it "raises an IOError when self is not readable" do
    -> { IOSpecs.closed_io.each_codepoint.to_a }.should.raise(IOError)
  end
end

describe "IO#each_codepoint" do
  before :each do
    @io = IOSpecs.io_fixture "lines.txt"
  end

  after :each do
    @io.close if @io
  end

  it "calls the given block" do
    r = []
    @io.each_codepoint { |c| r << c }
    r[24].should == 232
    r.last.should == 10
  end

  it "returns self" do
    @io.each_codepoint { |l| l }.should.equal?(@io)
  end
end

describe "IO#each_codepoint" do
  before :each do
    @io = IOSpecs.io_fixture("incomplete.txt")
  end

  after :each do
    @io.close if @io
  end

  it "raises an exception at incomplete character before EOF when conversion takes place" do
    -> { @io.each_codepoint {} }.should.raise(ArgumentError)
  end
end
