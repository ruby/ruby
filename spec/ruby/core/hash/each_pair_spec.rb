require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/iteration'
require_relative 'shared/each'
require_relative '../enumerable/shared/enumeratorized'

describe "Hash#each_pair" do
  it_behaves_like :hash_each, :each_pair
  it_behaves_like :hash_iteration_no_block, :each_pair
  it_behaves_like :enumeratorized_with_origin_size, :each_pair, { 1 => 2, 3 => 4, 5 => 6 }
end
