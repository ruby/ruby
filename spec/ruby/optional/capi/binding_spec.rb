require_relative 'spec_helper'

load_extension("binding")

describe "CApiBindingSpecs" do
  before :each do
    @b = CApiBindingSpecs.new
  end

  describe "Kernel#binding" do
    it "gives the top-most Ruby binding when called from C" do
      foo = 14
      b = @b.get_binding
      b.local_variable_get(:foo).should == 14
      b.local_variable_set :foo, 12
      foo.should == 12
    end
  end
end
