require_relative '../../../spec_helper'
require_relative 'shared/members'
require_relative 'shared/each'

describe "ObjectSpace::WeakMap#each_pair" do
  it_behaves_like :weakmap_members, -> map { a = []; map.each_pair{ |k,v| a << "#{k}#{v}" }; a }, %w[Ax By]
end

describe "ObjectSpace::WeakMap#each_key" do
  it_behaves_like :weakmap_each, :each_pair
end
