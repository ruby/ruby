require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/collect_concat'

describe "Enumerable#flat_map" do
  it_behaves_like :enumerable_collect_concat , :flat_map
end
