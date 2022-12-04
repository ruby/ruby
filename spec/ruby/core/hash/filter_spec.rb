require_relative '../../spec_helper'
require_relative 'shared/select'

describe "Hash#filter" do
  it_behaves_like :hash_select, :filter
end

describe "Hash#filter!" do
  it_behaves_like :hash_select!, :filter!
end
