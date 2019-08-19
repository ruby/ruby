require_relative '../../spec_helper'
require_relative 'shared/length'

describe "Symbol#length" do
  it_behaves_like :symbol_length, :length
end
