require_relative '../../../spec_helper'
require 'complex'
require_relative 'shared/exp'

describe "Math#exp" do
  it_behaves_like :complex_math_exp, :_, IncludesMath.new

  it "is a private instance method" do
    IncludesMath.should have_private_instance_method(:exp)
  end
end

describe "Math.exp" do
  it_behaves_like :complex_math_exp, :_, CMath
end
