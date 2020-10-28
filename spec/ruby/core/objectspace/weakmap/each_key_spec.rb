require_relative '../../../spec_helper'
require_relative 'shared/members'
require_relative 'shared/each'

describe "ObjectSpace::WeakMap#each_key" do
  it_behaves_like :weakmap_members, -> map { a = []; map.each_key{ |k| a << k }; a }, %w[A B]
end

describe "ObjectSpace::WeakMap#each_key" do
  it_behaves_like :weakmap_each, :each_key
end
