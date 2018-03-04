require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/entries'

describe "Enumerable#entries" do
  it_behaves_like :enumerable_entries , :entries
end
