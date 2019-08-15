require_relative '../../spec_helper'
require_relative 'shared/id2name'

describe "Symbol#id2name" do
  it_behaves_like :symbol_id2name, :id2name
end
