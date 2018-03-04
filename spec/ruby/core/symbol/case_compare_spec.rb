require_relative '../../spec_helper'

describe "Symbol#===" do
  it "returns true when the argument is a Symbol" do
    (Symbol === :ruby).should == true
  end

  it "returns false when the argument is a String" do
    (Symbol === 'ruby').should == false
  end
end
