require_relative '../../spec_helper'

describe "Set#hash" do
  it "is static" do
    Set[].hash.should == Set[].hash
    Set[1, 2, 3].hash.should == Set[1, 2, 3].hash
    Set[:a, "b", ?c].hash.should == Set[?c, "b", :a].hash

    Set[].hash.should_not == Set[1, 2, 3].hash
    Set[1, 2, 3].hash.should_not == Set[:a, "b", ?c].hash
  end

  ruby_version_is ""..."3.5" do
    # see https://github.com/jruby/jruby/issues/8393
    it "is equal to nil.hash for an uninitialized Set" do
      Set.allocate.hash.should == nil.hash
    end
  end
end
