require_relative '../../spec_helper'

describe "GC.stat" do
  it "supports access by key" do
    keys = [:heap_free_slots, :total_allocated_objects, :count]
    keys.each do |key|
      GC.stat(key).should be_kind_of(Integer)
    end
  end

  it "returns hash of values" do
    stat = GC.stat
    stat.should be_kind_of(Hash)
    stat.keys.should include(:count)
  end
end
