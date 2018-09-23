require 'complex'
require_relative '../../../spec_helper'
require_relative '../../../shared/math/atanh'
require_relative 'shared/atanh'

describe "Math#atanh" do
  math = Class.new { include ::CMath }.new
  it_behaves_like :math_atanh_base, :atanh, math
  it_behaves_like :complex_math_atanh_complex, :atanh, math

  it_behaves_like :math_atanh_private, :atanh, math
end

describe "Math.atanh" do
  it_behaves_like :math_atanh_base, :atanh, CMath
  it_behaves_like :complex_math_atanh_complex, :atanh, CMath
end
