require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/length'

describe "Array#length" do
  it_behaves_like :array_length, :length
end
