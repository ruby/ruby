require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Binding#receiver" do
  it "returns the object to which binding is bound" do
    obj = BindingSpecs::Demo.new(1)
    obj.get_binding.receiver.should == obj

    binding.receiver.should == self
  end
end
