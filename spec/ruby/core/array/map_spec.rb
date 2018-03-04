require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/collect'

describe "Array#map" do
  it_behaves_like :array_collect, :map
end

describe "Array#map!" do
  it_behaves_like :array_collect_b, :map!
end
