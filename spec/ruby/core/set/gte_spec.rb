require_relative '../../spec_helper'

describe "Set#>=" do
  it "is an alias of Set#superset?" do
    Set.instance_method(:>=).should == Set.instance_method(:superset?)
  end
end
