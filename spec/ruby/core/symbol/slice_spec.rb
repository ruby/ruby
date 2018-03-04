require_relative '../../spec_helper'
require_relative 'shared/slice'

describe "Symbol#slice" do
  it_behaves_like :symbol_slice, :slice
end
