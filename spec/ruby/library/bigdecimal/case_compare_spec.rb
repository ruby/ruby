require_relative '../../spec_helper'
require_relative 'shared/eql'


describe "BigDecimal#===" do
  it_behaves_like :bigdecimal_eql, :===
end
