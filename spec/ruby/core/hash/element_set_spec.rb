require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/store'

describe "Hash#[]=" do
  it_behaves_like :hash_store, :[]=
end
