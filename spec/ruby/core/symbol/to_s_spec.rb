require_relative '../../spec_helper'
require_relative 'shared/id2name'

describe "Symbol#to_s" do
  it_behaves_like :symbol_id2name, :to_s
end
