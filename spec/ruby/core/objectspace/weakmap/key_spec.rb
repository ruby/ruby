require_relative '../../../spec_helper'
require_relative 'shared/include'

describe "ObjectSpace::WeakMap#key?" do
  it_behaves_like :weakmap_include?, :key?
end
