require_relative '../../spec_helper'
require_relative 'fixtures/common'
require_relative 'shared/exist'

describe "Dir.exist?" do
  before :all do
    DirSpecs.create_mock_dirs
  end

  after :all do
    DirSpecs.delete_mock_dirs
  end

  it_behaves_like :dir_exist, :exist?
end

ruby_version_is "3.2" do
  describe "Dir.exists?" do
    it "has been removed" do
      Dir.should_not.respond_to?(:exists?)
    end
  end
end
