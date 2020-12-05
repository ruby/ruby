require_relative '../../../spec_helper'
require 'set'
require_relative 'shared/collect'

describe "SortedSet#map!" do
  it_behaves_like :sorted_set_collect_bang, :map!
end
