require_relative '../../../spec_helper'
require_relative 'shared/length'
require 'set'

describe "SortedSet#size" do
  it_behaves_like :sorted_set_length, :size
end
