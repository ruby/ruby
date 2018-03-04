require_relative '../../spec_helper'
require_relative 'shared/collect'

describe "Matrix#map" do
  it_behaves_like :collect, :map
end
