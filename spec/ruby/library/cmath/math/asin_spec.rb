require_relative '../../../spec_helper'

ruby_version_is ''...'2.7' do
  require 'complex'
  require_relative 'shared/asin'

  describe "Math#asin" do
    it_behaves_like :complex_math_asin, :_, IncludesMath.new

    it "is a private instance method" do
      IncludesMath.should have_private_instance_method(:asin)
    end
  end

  describe "Math.asin" do
    it_behaves_like :complex_math_asin, :_, CMath
  end
end
