require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/replace'

describe "Hash#replace" do
  it_behaves_like :hash_replace, :replace
end
