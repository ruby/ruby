require_relative '../../../spec_helper'

ruby_version_is ''...'2.7' do
  require 'complex'
  require_relative 'shared/log10'

  describe "Math#log10" do
    it_behaves_like :complex_math_log10, :_, IncludesMath.new

    it "is a private instance method" do
      IncludesMath.should have_private_instance_method(:log10)
    end
  end

  describe "Math.log10" do
    it_behaves_like :complex_math_log10, :_, CMath
  end
end
