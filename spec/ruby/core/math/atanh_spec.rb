require_relative '../../spec_helper'
require_relative '../../shared/math/atanh'

describe "Math.atanh" do
  it_behaves_like :math_atanh_base, :atanh, Math
  it_behaves_like :math_atanh_no_complex, :atanh, Math
end

describe "Math#atanh" do
  math = Class.new { include ::Math }.new
  it_behaves_like :math_atanh_private   , :atanh
  it_behaves_like :math_atanh_base      , :atanh, math
  it_behaves_like :math_atanh_no_complex, :atanh, math
end
