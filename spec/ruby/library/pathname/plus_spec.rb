require_relative '../../spec_helper'
require 'pathname'

describe "Pathname#+" do
  it "appends a pathname to self" do
    p = Pathname.new("/usr")
    (p + "bin/ruby").should == Pathname.new("/usr/bin/ruby")
  end
end
