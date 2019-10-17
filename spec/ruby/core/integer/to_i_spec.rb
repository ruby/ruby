require_relative '../../spec_helper'
require_relative 'shared/to_i'

describe "Integer#to_i" do
  it_behaves_like :integer_to_i, :to_i
end
