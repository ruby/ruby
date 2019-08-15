require_relative '../../spec_helper'
require_relative '../../fixtures/math/common'
require_relative '../../shared/math/atanh'

describe "Math.atanh" do
  it_behaves_like :math_atanh_base, :atanh, Math
  it_behaves_like :math_atanh_no_complex, :atanh, Math
end

describe "Math#atanh" do
  it_behaves_like :math_atanh_private, :atanh
  it_behaves_like :math_atanh_base, :atanh, IncludesMath.new
  it_behaves_like :math_atanh_no_complex, :atanh, IncludesMath.new
end
