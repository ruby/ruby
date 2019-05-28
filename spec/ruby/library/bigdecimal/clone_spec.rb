require_relative '../../spec_helper'
require_relative 'shared/clone'

describe "BigDecimal#dup" do
  it_behaves_like :bigdecimal_clone, :clone
end
