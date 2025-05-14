require_relative 'spec_helper'

load_extension("binding")

describe "CApiBindingSpecs" do
  before :each do
    @b = CApiBindingSpecs.new
  end

  describe "Kernel#binding" do
    it "raises when called from C" do
      foo = 14
      -> { @b.get_binding }.should raise_error(RuntimeError)
    end
  end
end
