require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/length'

describe "Hash#size" do
  it_behaves_like :hash_length, :size
end
