require_relative '../../spec_helper'
require_relative 'shared/index'

describe "Array#find_index" do
  it_behaves_like :array_index, :find_index
end
