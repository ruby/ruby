require_relative '../../spec_helper'
require_relative 'fixtures/common'
require_relative 'shared/path'

describe "Dir#to_path" do
  before :all do
    DirSpecs.create_mock_dirs
  end

  after :all do
    DirSpecs.delete_mock_dirs
  end

  it_behaves_like :dir_path, :to_path
end
