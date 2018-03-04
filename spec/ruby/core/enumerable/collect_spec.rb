require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/collect'

describe "Enumerable#collect" do
  it_behaves_like :enumerable_collect , :collect
end
