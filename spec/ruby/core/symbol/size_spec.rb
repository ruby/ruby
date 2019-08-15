require_relative '../../spec_helper'
require_relative 'shared/length'

describe "Symbol#size" do
  it_behaves_like :symbol_length, :size
end
