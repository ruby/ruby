require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/replace'

describe "Array#replace" do
  it_behaves_like :array_replace, :replace
end
