require_relative '../../spec_helper'
require_relative '../enumerable/shared/enumeratorized'
require_relative 'shared/select'

describe "ENV.select!" do
  it_behaves_like :env_select!, :select!
  it_behaves_like :enumeratorized_with_origin_size, :select!, ENV
end

describe "ENV.select" do
  it_behaves_like :env_select, :select
  it_behaves_like :enumeratorized_with_origin_size, :select, ENV
end
