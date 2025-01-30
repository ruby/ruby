require_relative '../spec_helper'

ruby_version_is "3.2" do
  describe "CVE-2024-49761 is resisted by" do
    it "the Regexp implementation handling that regular expression in linear time" do
      Regexp.linear_time?(/&#0*((?:\d+)|(?:x[a-fA-F0-9]+));/).should == true
    end
  end
end
