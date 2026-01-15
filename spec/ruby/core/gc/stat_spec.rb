require_relative '../../spec_helper'

describe "GC.stat" do
  it "returns hash of values" do
    stat = GC.stat
    stat.should be_kind_of(Hash)
    stat.keys.should.include?(:count)
  end

  it "updates the given hash values" do
    hash = { count: "hello", __other__: "world" }
    stat = GC.stat(hash)

    stat.should be_kind_of(Hash)
    stat.should equal hash
    stat[:count].should be_kind_of(Integer)
    stat[:__other__].should == "world"
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

  it "raises an error if argument is not nil, a symbol, or a hash" do
    -> { GC.stat(7) }.should raise_error(TypeError, "non-hash or symbol given")
  end

  it "raises an error if an unknown key is given" do
    -> { GC.stat(:foo) }.should raise_error(ArgumentError, "unknown key: foo")
  end
end
