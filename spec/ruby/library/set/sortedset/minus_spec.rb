require_relative '../../../spec_helper'
require 'set'
require_relative 'shared/difference'

describe "SortedSet#-" do
  it_behaves_like :sorted_set_difference, :-
end
