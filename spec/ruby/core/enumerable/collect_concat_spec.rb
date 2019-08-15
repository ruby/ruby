require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/collect_concat'

describe "Enumerable#collect_concat" do
  it_behaves_like :enumerable_collect_concat , :collect_concat
end
