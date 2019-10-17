require_relative '../../spec_helper'

describe "GC.count" do
  it "returns an integer" do
    GC.count.should be_kind_of(Integer)
  end

  it "increases as collections are run" do
    count_before = GC.count
    i = 0
    while GC.count <= count_before and i < 10
      GC.start
      i += 1
    end
    GC.count.should > count_before
  end
end
