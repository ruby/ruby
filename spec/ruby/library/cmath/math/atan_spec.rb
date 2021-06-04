require_relative '../../../spec_helper'

ruby_version_is ''...'2.7' do
  require 'complex'
  require_relative 'shared/atan'

  describe "Math#atan" do
    it_behaves_like :complex_math_atan, :_, IncludesMath.new

    it "is a private instance method" do
      IncludesMath.should have_private_instance_method(:atan)
    end
  end

  describe "Math.atan" do
    it_behaves_like :complex_math_atan, :_, CMath
  end
end
