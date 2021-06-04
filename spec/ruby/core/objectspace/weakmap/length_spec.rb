require_relative '../../../spec_helper'
require_relative 'shared/size'

describe "ObjectSpace::WeakMap#length" do
  it_behaves_like :weakmap_size, :length
end
