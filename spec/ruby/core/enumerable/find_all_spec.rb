require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/find_all'

describe "Enumerable#find_all" do
  it_behaves_like :enumerable_find_all , :find_all
end
