require_relative '../../spec_helper'
require_relative 'shared/intersection'
require 'set'

describe "Set#intersection" do
  it_behaves_like :set_intersection, :intersection
end

describe "Set#&" do
  it_behaves_like :set_intersection, :&
end
