require_relative '../../../spec_helper'
require 'complex'
require_relative 'shared/cos'

describe "Math#cos" do
  it_behaves_like :complex_math_cos, :_, IncludesMath.new

  it "is a private instance method" do
    IncludesMath.should have_private_instance_method(:cos)
  end
end

describe "Math.cos" do
  it_behaves_like :complex_math_cos, :_, CMath
end
