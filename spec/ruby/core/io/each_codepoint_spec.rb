require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/codepoints'

# See redmine #1667
describe "IO#each_codepoint" do
  it_behaves_like :io_codepoints, :each_codepoint
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
    @io.each_codepoint { |l| l }.should equal(@io)
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
    -> { @io.each_codepoint {} }.should raise_error(ArgumentError)
  end
end
