require_relative '../../spec_helper'
require_relative 'fixtures/common'
require_relative 'shared/closed'
require_relative 'shared/pos'

describe "Dir#tell" do
  before :all do
    DirSpecs.create_mock_dirs
  end

  after :all do
    DirSpecs.delete_mock_dirs
  end

  it_behaves_like :dir_pos, :tell

  it_behaves_like :dir_closed, :tell
end
