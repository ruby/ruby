require_relative '../../../spec_helper'
require 'complex'
require_relative 'shared/cosh'

describe "Math#cosh" do
  it_behaves_like :complex_math_cosh, :_, IncludesMath.new

  it "is a private instance method" do
    IncludesMath.should have_private_instance_method(:cosh)
  end
end

describe "Math.cosh" do
  it_behaves_like :complex_math_cosh, :_, CMath
end
