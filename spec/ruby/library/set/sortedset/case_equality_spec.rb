require_relative '../../../spec_helper'
require_relative 'shared/include'
require 'set'

describe "SortedSet#===" do
  it_behaves_like :sorted_set_include, :===
end
