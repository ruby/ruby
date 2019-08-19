require_relative '../../../spec_helper'
require 'complex'
require_relative 'shared/tanh'

describe "Math#tanh" do
  it_behaves_like :complex_math_tanh, :_, IncludesMath.new

  it "is a private instance method" do
    IncludesMath.should have_private_instance_method(:tanh)
  end
end

describe "Math.tanh" do
  it_behaves_like :complex_math_tanh, :_, CMath
end
