require_relative '../../spec_helper'

describe "GC.stat" do
  it "returns hash of values" do
    stat = GC.stat
    stat.should.is_a?(Hash)
    stat.keys.should.include?(:count)
  end

  it "updates the given hash values" do
    hash = { count: "hello", __other__: "world" }
    stat = GC.stat(hash)

    stat.should.is_a?(Hash)
    stat.should.equal? hash
    stat[:count].should.is_a?(Integer)
    stat[:__other__].should == "world"
  end

  it "the values are all Integer since rb_gc_stat() returns size_t" do
    GC.stat.values.each { |value| value.should.is_a?(Integer) }
  end

  it "can return a single value" do
    GC.stat(:count).should.is_a?(Integer)
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
    GC.stat(:count).should.is_a?(Integer)
    GC.stat[:count].should.is_a?(Integer)
  end

  it "provides some number for heap_free_slots" do
    GC.stat(:heap_free_slots).should.is_a?(Integer)
    GC.stat[:heap_free_slots].should.is_a?(Integer)
  end

  it "provides some number for total_allocated_objects" do
    GC.stat(:total_allocated_objects).should.is_a?(Integer)
    GC.stat[:total_allocated_objects].should.is_a?(Integer)
  end

  it "raises an error if argument is not nil, a symbol, or a hash" do
    -> { GC.stat(7) }.should.raise(TypeError, "non-hash or symbol given")
  end

  it "raises an error if an unknown key is given" do
    -> { GC.stat(:foo) }.should.raise(ArgumentError, "unknown key: foo")
  end
end
