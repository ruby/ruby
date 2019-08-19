require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/length'

describe "Hash#length" do
  it_behaves_like :hash_length, :length
end
