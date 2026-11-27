require_relative '../../spec_helper'

describe "Symbol#slice" do
  it "is an alias of Symbol#[]" do
    Symbol.instance_method(:slice).should == Symbol.instance_method(:[])
  end
end
