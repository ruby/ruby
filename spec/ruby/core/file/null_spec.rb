require_relative '../../spec_helper'

describe "File::NULL" do
  platform_is :windows do
    it "returns NUL as a string" do
      File::NULL.should == 'NUL'
    end
  end

  platform_is_not :windows do
    it "returns /dev/null as a string" do
      File::NULL.should == '/dev/null'
    end
  end
end
