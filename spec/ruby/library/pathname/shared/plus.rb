require 'pathname'

describe :pathname_plus, shared: true do
  it "appends a pathname to self" do
    p = Pathname.new("/usr")
    p.send(@method, "bin/ruby").should == Pathname.new("/usr/bin/ruby")
  end
end
