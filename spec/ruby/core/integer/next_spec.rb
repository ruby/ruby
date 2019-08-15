require_relative '../../spec_helper'
require_relative 'shared/next'

describe "Integer#next" do
  it_behaves_like :integer_next, :next
end
