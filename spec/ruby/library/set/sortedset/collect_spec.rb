require_relative '../../../spec_helper'
require 'set'
require_relative 'shared/collect'

describe "SortedSet#collect!" do
  it_behaves_like :sorted_set_collect_bang, :collect!
end
