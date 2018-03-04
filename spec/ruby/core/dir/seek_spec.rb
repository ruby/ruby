require_relative '../../spec_helper'
require_relative 'fixtures/common'
require_relative 'shared/pos'

describe "Dir#seek" do
  before :all do
    DirSpecs.create_mock_dirs
  end

  after :all do
    DirSpecs.delete_mock_dirs
  end

  it "returns the Dir instance" do
    @dir.seek(@dir.pos).should == @dir
  end

  it_behaves_like :dir_pos_set, :seek
end
