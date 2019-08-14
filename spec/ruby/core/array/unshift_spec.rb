require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/unshift'

describe "Array#unshift" do
  it_behaves_like :array_unshift, :unshift
end
