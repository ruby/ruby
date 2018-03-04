require_relative '../../spec_helper'
require_relative '../../shared/complex/numeric/real'
require_relative 'fixtures/classes'

describe "Numeric#real" do
  it_behaves_like :numeric_real, :real
end

describe "Numeric#real?" do
  it "returns true" do
    NumericSpecs::Subclass.new.real?.should == true
  end
end
