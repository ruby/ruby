require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/values_at'

describe "Hash#values_at" do
  it_behaves_like :hash_values_at, :values_at
end
