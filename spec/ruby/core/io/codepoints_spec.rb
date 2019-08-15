require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/codepoints'

# See redmine #1667
describe "IO#codepoints" do
  it_behaves_like :io_codepoints, :codepoints
end

describe "IO#codepoints" do
  before :each do
    @io = IOSpecs.io_fixture "lines.txt"
  end

  after :each do
    @io.close unless @io.closed?
  end

  it "calls the given block" do
    r = []
    @io.codepoints { |c| r << c }
    r[24].should == 232
    r.last.should == 10
  end
end
