require_relative '../../spec_helper'

describe "TrueClass#|" do
  it "returns true" do
    (true | true).should == true
    (true | false).should == true
    (true | nil).should == true
    (true | "").should == true
    (true | mock('x')).should == true
  end
end
