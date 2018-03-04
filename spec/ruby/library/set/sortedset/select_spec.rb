require_relative '../../../spec_helper'
require_relative 'shared/select'
require 'set'

describe "SortedSet#select!" do
  it_behaves_like :sorted_set_select_bang, :select!
end
