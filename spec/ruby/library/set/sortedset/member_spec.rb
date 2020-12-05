require_relative '../../../spec_helper'
require_relative 'shared/include'
require 'set'

describe "SortedSet#member?" do
  it_behaves_like :sorted_set_include, :member?
end
