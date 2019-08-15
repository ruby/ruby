require_relative '../../../spec_helper'
require 'complex'
require_relative 'shared/sinh'

describe "Math#sinh" do
  it_behaves_like :complex_math_sinh, :_, IncludesMath.new

  it "is a private instance method" do
    IncludesMath.should have_private_instance_method(:sinh)
  end
end

describe "Math.sinh" do
  it_behaves_like :complex_math_sinh, :_, CMath
end
