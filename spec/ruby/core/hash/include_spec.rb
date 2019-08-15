require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/key'

describe "Hash#include?" do
  it_behaves_like :hash_key_p, :include?
end
