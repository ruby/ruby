require_relative '../../../spec_helper'

ruby_version_is ''...'2.7' do
  require 'complex'
  require_relative 'shared/acosh'

  describe "Math#acosh" do
    it_behaves_like :complex_math_acosh, :_, IncludesMath.new

    it "is a private instance method" do
      IncludesMath.should have_private_instance_method(:acosh)
    end
  end

  describe "Math.acosh" do
    it_behaves_like :complex_math_acosh, :_, CMath
  end
end
