require_relative '../../../spec_helper'
require 'set'
require_relative 'shared/add'

describe "SortedSet#<<" do
  it_behaves_like :sorted_set_add, :<<
end
