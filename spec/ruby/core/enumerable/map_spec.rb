require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/collect'

describe "Enumerable#map" do
  it_behaves_like :enumerable_collect , :map
end
