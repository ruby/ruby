require_relative '../../spec_helper'
require_relative 'shared/succ'

describe "Symbol#next" do
  it_behaves_like :symbol_succ, :next
end
