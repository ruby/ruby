require_relative '../../spec_helper'
require_relative 'fixtures/common'
require_relative 'shared/closed'

describe "Dir#rewind" do
  before :all do
    DirSpecs.create_mock_dirs
  end

  after :all do
    DirSpecs.delete_mock_dirs
  end

  before :each do
    @dir = Dir.open DirSpecs.mock_dir
  end

  after :each do
    @dir.close
  end

  it "resets the next read to start from the first entry" do
    a = @dir.read
    b = @dir.read
    a.should_not == b
    @dir.rewind
    c = @dir.read
    c.should == a
  end

  it "returns the Dir instance" do
    @dir.rewind.should == @dir
  end

  it_behaves_like :dir_closed, :rewind
end
