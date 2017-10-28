require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../../../shared/file/zero', __FILE__)

describe "File.empty?" do
  ruby_version_is "2.4" do
    it_behaves_like :file_zero, :empty?, File
    it_behaves_like :file_zero_missing, :empty?, File

    platform_is :solaris do
      it "returns false for /dev/null" do
        File.empty?('/dev/null').should == true
      end
    end
  end
end
