require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../shared/select', __FILE__)

describe "Hash#select" do
  it_behaves_like :hash_select, :select
end

describe "Hash#select!" do
  it_behaves_like :hash_select!, :select!
end
