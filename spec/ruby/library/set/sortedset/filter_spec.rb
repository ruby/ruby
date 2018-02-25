require File.expand_path('../../../../spec_helper', __FILE__)
require File.expand_path('../shared/select', __FILE__)
require 'set'

describe "SortedSet#filter!" do
  it_behaves_like :sorted_set_select_bang, :filter!
end
