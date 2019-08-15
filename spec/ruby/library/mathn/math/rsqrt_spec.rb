require_relative '../../../spec_helper'

ruby_version_is ''...'2.5' do
  require_relative 'shared/rsqrt'

  describe "Math#rsqrt" do
    it_behaves_like :mathn_math_rsqrt, :_, IncludesMath.new

    it "is a private instance method" do
      IncludesMath.should have_private_instance_method(:rsqrt)
    end
  end

  describe "Math.rsqrt" do
    it_behaves_like :mathn_math_rsqrt, :_, Math
  end
end
