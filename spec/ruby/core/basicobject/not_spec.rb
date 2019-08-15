require_relative '../../spec_helper'

describe "BasicObject#!" do
  it "is a public instance method" do
    BasicObject.should have_public_instance_method(:'!')
  end

  it "returns false" do
    (!BasicObject.new).should be_false
  end
end
