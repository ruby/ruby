require_relative '../../../spec_helper'

ruby_version_is ''...'2.7' do
  require 'complex'
  require_relative 'shared/atan2'

  describe "Math#atan2" do
    it_behaves_like :complex_math_atan2, :_, IncludesMath.new

    it "is a private instance method" do
      IncludesMath.should have_private_instance_method(:atan2)
    end
  end

  describe "Math.atan2" do
    it_behaves_like :complex_math_atan2, :_, CMath
  end
end
