require_relative '../../../spec_helper'

ruby_version_is ''...'2.7' do
  require 'complex'
  require_relative 'shared/asinh'

  describe "Math#asinh" do
    it_behaves_like :complex_math_asinh, :_, IncludesMath.new

    it "is a private instance method" do
      IncludesMath.should have_private_instance_method(:asinh)
    end
  end

  describe "Math.asinh" do
    it_behaves_like :complex_math_asinh, :_, CMath
  end
end
