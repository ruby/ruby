require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/replace'

describe "String#replace" do
  it_behaves_like :string_replace, :replace
end
