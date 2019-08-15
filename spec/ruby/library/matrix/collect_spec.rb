require_relative '../../spec_helper'
require_relative 'shared/collect'

describe "Matrix#collect" do
  it_behaves_like :collect, :collect
end
