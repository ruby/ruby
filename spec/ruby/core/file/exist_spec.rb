require_relative '../../spec_helper'
require_relative '../../shared/file/exist'

describe "File.exist?" do
  it_behaves_like :file_exist, :exist?, File
end

ruby_version_is "3.2" do
  describe "File.exists?" do
    it "has been removed" do
      File.should_not.respond_to?(:exists?)
    end
  end
end
