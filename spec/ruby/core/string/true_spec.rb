require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "String#true?" do
  it "'true' returns true" do
    "true".true?.should == true
  end

  it "'false' returns false" do
    "false".true?.should == false
  end

  it "'' returns false" do
    "".true?.should == false
  end
  
  it "anything else returns false" do
    "anything else".true?.should == false
  end
end
