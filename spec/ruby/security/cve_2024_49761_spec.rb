require_relative '../spec_helper'

describe "CVE-2024-49761 is resisted by" do
  it "the Regexp implementation handling that regular expression in linear time" do
    Regexp.linear_time?(/&#0*((?:\d+)|(?:x[a-fA-F0-9]+));/).should == true
  end
end
