require_relative '../../../spec_helper'
require_relative 'shared/members'

describe "ObjectSpace::WeakMap#values" do
  it_behaves_like :weakmap_members, -> map { map.values }, %w[x y]
end
