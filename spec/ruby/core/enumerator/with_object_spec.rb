require_relative '../../spec_helper'

describe "Enumerator#with_object" do
  it "is an alias of Enumerator#each_with_object" do
    Enumerator.instance_method(:with_object).should == Enumerator.instance_method(:each_with_object)
  end
end
