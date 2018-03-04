require_relative '../../spec_helper'
require_relative 'shared/succ'

describe "Symbol#succ" do
  it_behaves_like :symbol_succ, :succ
end
