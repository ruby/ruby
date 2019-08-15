require_relative '../../spec_helper'
require_relative 'shared/divide'

describe "Complex#quo" do
  it_behaves_like :complex_divide, :quo
end
