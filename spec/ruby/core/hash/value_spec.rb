require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/value'

describe "Hash#value?" do
  it_behaves_like :hash_value_p, :value?
end
