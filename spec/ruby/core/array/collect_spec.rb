require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/collect'

describe "Array#collect" do
  it_behaves_like :array_collect, :collect
end

describe "Array#collect!" do
  it_behaves_like :array_collect_b, :collect!
end
