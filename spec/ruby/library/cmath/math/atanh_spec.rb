require_relative '../../../spec_helper'

ruby_version_is ''...'2.7' do
  require 'complex'
  require_relative '../../../fixtures/math/common'
  require_relative '../../../shared/math/atanh'
  require_relative 'shared/atanh'

  describe "Math#atanh" do
    it_behaves_like :math_atanh_base, :atanh, IncludesMath.new
    it_behaves_like :complex_math_atanh_complex, :atanh, IncludesMath.new

    it_behaves_like :math_atanh_private, :atanh, IncludesMath.new
  end

  describe "Math.atanh" do
    it_behaves_like :math_atanh_base, :atanh, CMath
    it_behaves_like :complex_math_atanh_complex, :atanh, CMath
  end
end
