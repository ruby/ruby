require_relative '../../../spec_helper'
require 'set'

describe "SortedSet#flatten_merge" do
  it "is protected" do
    SortedSet.should have_protected_instance_method("flatten_merge")
  end
end
