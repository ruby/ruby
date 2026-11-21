require_relative '../../spec_helper'

describe "Set#>" do
  it "is an alias of Set#proper_superset?" do
    Set.instance_method(:>).should == Set.instance_method(:proper_superset?)
  end
end
