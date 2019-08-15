require_relative '../../spec_helper'
require_relative '../../shared/file/zero'

describe "FileTest.zero?" do
  it_behaves_like :file_zero, :zero?, FileTest
  it_behaves_like :file_zero_missing, :zero?, FileTest

  platform_is :solaris do
    it "returns false for /dev/null" do
      File.zero?('/dev/null').should == true
    end
  end
end
