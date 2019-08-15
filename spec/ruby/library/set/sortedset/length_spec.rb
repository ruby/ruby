require_relative '../../../spec_helper'
require_relative 'shared/length'
require 'set'

describe "SortedSet#length" do
  it_behaves_like :sorted_set_length, :length
end
