require_relative '../../../spec_helper'
require_relative 'shared/union'
require 'set'

describe "SortedSet#+" do
  it_behaves_like :sorted_set_union, :+
end
