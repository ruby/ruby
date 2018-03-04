require_relative '../../spec_helper'
require_relative 'shared/next'

describe "Integer#succ" do
  it_behaves_like :integer_next, :succ
end
