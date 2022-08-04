# -*- encoding: us-ascii -*-

require_relative '../../../spec_helper'

describe "Enumerator::Lazy" do
  it "is a subclass of Enumerator" do
    Enumerator::Lazy.superclass.should equal(Enumerator)
  end

  it "defines lazy versions of a whitelist of Enumerator methods" do
    lazy_methods = [
      :chunk, :collect, :collect_concat, :drop, :drop_while, :enum_for,
      :find_all, :flat_map, :force, :grep, :grep_v, :lazy, :map, :reject,
      :select, :slice_after, :slice_before, :slice_when, :take, :take_while,
      :to_enum, :zip
    ]
    lazy_methods += [:chunk_while, :uniq]

    ruby_version_is '3.1' do
      lazy_methods += [:compact]
    end

    Enumerator::Lazy.instance_methods(false).should include(*lazy_methods)
  end
end

describe "Enumerator::Lazy#lazy" do
  it "returns self" do
    lazy = (1..3).to_enum.lazy
    lazy.lazy.should equal(lazy)
  end
end

ruby_version_is '3.1' do
  describe "Enumerator::Lazy#compact" do
    it 'returns array without nil elements' do
      arr = [1, nil, 3, false, 5].to_enum.lazy.compact
      arr.should be_an_instance_of(Enumerator::Lazy)
      arr.force.should == [1, 3, false, 5]
    end
  end
end
