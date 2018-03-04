require_relative '../../spec_helper'
require_relative 'shared/quo'
require 'bigdecimal'

describe "BigDecimal#/" do
  it_behaves_like :bigdecimal_quo, :/, []
end
