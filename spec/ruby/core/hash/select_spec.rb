require_relative '../../spec_helper'
require_relative 'shared/select'

describe "Hash#select" do
  it_behaves_like :hash_select, :select
end

describe "Hash#select!" do
  it_behaves_like :hash_select!, :select!
end
