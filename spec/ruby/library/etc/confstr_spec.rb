require File.expand_path('../../../spec_helper', __FILE__)
require 'etc'

platform_is_not :windows, :android do
  describe "Etc.confstr" do
    it "returns a String for Etc::CS_PATH" do
      Etc.confstr(Etc::CS_PATH).should be_an_instance_of(String)
    end

    it "raises Errno::EINVAL for unknown configuration variables" do
      -> { Etc.confstr(-1) }.should raise_error(Errno::EINVAL)
    end
  end
end
