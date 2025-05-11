require_relative '../../spec_helper'
require_relative 'shared/add'

describe "Set#add" do
  it_behaves_like :set_add, :add
end

describe "Set#add?" do
  before :each do
    @set = Set.new
  end

  it "adds the passed Object to self" do
    @set.add?("cat")
    @set.should include("cat")
  end

  it "returns self when the Object has not yet been added to self" do
    @set.add?("cat").should equal(@set)
  end

  it "returns nil when the Object has already been added to self" do
    @set.add?("cat")
    @set.add?("cat").should be_nil
  end
end
