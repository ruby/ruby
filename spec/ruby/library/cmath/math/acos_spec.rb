require_relative '../../../spec_helper'

ruby_version_is ''...'2.7' do
  require 'complex'
  require_relative 'shared/acos'

  describe "Math#acos" do
    it_behaves_like :complex_math_acos, :_, IncludesMath.new

    it "is a private instance method" do
      IncludesMath.should have_private_instance_method(:acos)
    end
  end

  describe "Math.acos" do
    it_behaves_like :complex_math_acos, :_, CMath
  end
end
