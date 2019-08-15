require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/index'

describe "Hash#index" do
  it_behaves_like :hash_index, :index
end
