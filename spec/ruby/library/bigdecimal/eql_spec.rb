require_relative '../../spec_helper'
require_relative 'shared/eql'

describe "BigDecimal#eql?" do
  it_behaves_like :bigdecimal_eql, :eql?
end
