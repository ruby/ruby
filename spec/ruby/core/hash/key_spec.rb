require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/key'
require_relative 'shared/index'

describe "Hash#key?" do
  it_behaves_like :hash_key_p, :key?
end

describe "Hash#key" do
  it_behaves_like :hash_index, :key
end
