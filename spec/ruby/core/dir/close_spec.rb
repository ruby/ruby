require_relative '../../spec_helper'
require_relative 'fixtures/common'
describe "Dir#close" do
  before :all do
    DirSpecs.create_mock_dirs
  end

  after :all do
    DirSpecs.delete_mock_dirs
  end

  it "does not raise an IOError even if the Dir instance is closed" do
    dir = Dir.open DirSpecs.mock_dir
    dir.close
    lambda {
      dir.close
    }.should_not raise_error(IOError)
  end
end
