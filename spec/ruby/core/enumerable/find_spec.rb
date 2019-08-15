require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/find'

describe "Enumerable#find" do
  it_behaves_like :enumerable_find , :find
end
