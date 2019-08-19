require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/update'

describe "Hash#update" do
  it_behaves_like :hash_update, :update
end
