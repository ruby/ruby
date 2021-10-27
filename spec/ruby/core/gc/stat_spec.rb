require_relative '../../spec_helper'

describe "GC.stat" do
  it "returns hash of values" do
    stat = GC.stat
    stat.should be_kind_of(Hash)
    stat.keys.should.include?(:count)
  end

  it "the values are all Integer since rb_gc_stat() returns size_t" do
    GC.stat.values.each { |value| value.should be_kind_of(Integer) }
  end

  it "can return a single value" do
    GC.stat(:count).should be_kind_of(Integer)
  end

  it "increases count after GC is run" do
    count = GC.stat(:count)
    GC.start
    GC.stat(:count).should > count
  end

  it "increases major_gc_count after GC is run" do
    count = GC.stat(:major_gc_count)
    GC.start
    GC.stat(:major_gc_count).should > count
  end

  it "provides some number for count" do
    GC.stat(:count).should be_kind_of(Integer)
    GC.stat[:count].should be_kind_of(Integer)
  end

  it "provides some number for heap_free_slots" do
    GC.stat(:heap_free_slots).should be_kind_of(Integer)
    GC.stat[:heap_free_slots].should be_kind_of(Integer)
  end

  it "provides some number for total_allocated_objects" do
    GC.stat(:total_allocated_objects).should be_kind_of(Integer)
    GC.stat[:total_allocated_objects].should be_kind_of(Integer)
  end
end
