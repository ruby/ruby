require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/value'

describe "Hash#has_value?" do
  it_behaves_like :hash_value_p, :has_value?
end
