require_relative '../spec_helper'

describe "The -0 command line option" do
  it "sets $/ and $-0" do
    ruby_exe("puts $/, $-0", options: "-072").should == ":\n:\n"
  end

  ruby_version_is "4.0" do
    it "sets $/ and $-0 as a frozen string" do
      ruby_exe("puts $/.frozen?, $-0.frozen?", options: "-072").should == "true\ntrue\n"
    end
  end
end
