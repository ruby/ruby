require_relative '../../spec_helper'
require 'etc'

platform_is_not :windows, :android do
  describe "Etc.confstr" do
    it "returns a String for Etc::CS_PATH" do
      Etc.confstr(Etc::CS_PATH).should.instance_of?(String)
    end

    it "raises Errno::EINVAL for unknown configuration variables" do
      -> { Etc.confstr(-1) }.should.raise(Errno::EINVAL)
    end
  end
end
