require_relative '../../spec_helper'
require_relative '../../shared/file/exist'

describe "FileTest.exist?" do
  it_behaves_like :file_exist, :exist?, FileTest
end

ruby_version_is "3.2" do
  describe "FileTest.exists?" do
    it "has been removed" do
      FileTest.should_not.respond_to?(:exists?)
    end
  end
end
