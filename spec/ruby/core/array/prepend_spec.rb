require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/unshift'

describe "Array#prepend" do
  it_behaves_like :array_unshift, :prepend
end
