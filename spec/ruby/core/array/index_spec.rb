require_relative '../../spec_helper'
require_relative 'shared/index'

describe "Array#index" do
  it_behaves_like :array_index, :index
end
