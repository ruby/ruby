require_relative '../../spec_helper'
require_relative 'shared/to_int'
require 'bigdecimal'


describe "BigDecimal#to_int" do
  it_behaves_like :bigdecimal_to_int, :to_int
end
