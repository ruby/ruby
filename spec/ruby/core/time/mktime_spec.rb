require_relative '../../spec_helper'

describe "Time.mktime" do
  it "is an alias of Time.local" do
    Time.method(:mktime).should == Time.method(:local)
  end
end
