require_relative '../../../spec_helper'

ruby_version_is ''...'2.7' do
  require 'complex'
  require_relative 'shared/log'

  describe "Math#log" do
    it_behaves_like :complex_math_log, :_, IncludesMath.new

    it "is a private instance method" do
      IncludesMath.should have_private_instance_method(:log)
    end
  end

  describe "Math.log" do
    it_behaves_like :complex_math_log, :_, CMath
  end
end
