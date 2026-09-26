require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "String#false?" do
  it "'false' returns true" do
    "false".false?.should == true
  end

  it "'true' returns false" do
    "true".false?.should == false
  end

  it "'' returns false" do
    "".false?.should == false
  end
  
  it "anything else returns false" do
    "anything else".false?.should == false
  end
end
