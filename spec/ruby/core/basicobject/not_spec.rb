require_relative '../../spec_helper'

describe "BasicObject#!" do
  it "is a public instance method" do
    BasicObject.public_instance_methods(false).should.include?(:'!')
  end

  it "returns false" do
    (!BasicObject.new).should == false
  end
end
