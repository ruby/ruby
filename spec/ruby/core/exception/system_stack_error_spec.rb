require_relative '../../spec_helper'

describe "SystemStackError" do
  it "is a subclass of Exception" do
    SystemStackError.superclass.should == Exception
  end
end
