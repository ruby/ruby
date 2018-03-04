require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/to_s'

describe "Hash#inspect" do
  it_behaves_like :hash_to_s, :inspect
end
