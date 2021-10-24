require_relative 'spec_helper'

load_extension("gc")

describe "CApiGCSpecs" do
  before :each do
    @f = CApiGCSpecs.new
  end

  it "correctly gets the value from a registered address" do
    @f.registered_tagged_address.should == 10
    @f.registered_tagged_address.should equal(@f.registered_tagged_address)
    @f.registered_reference_address.should == "Globally registered data"
    @f.registered_reference_address.should equal(@f.registered_reference_address)
  end

  describe "rb_gc_enable" do

    after do
      GC.enable
    end

    it "enables GC when disabled" do
      GC.disable
      @f.rb_gc_enable.should be_true
    end

    it "GC stays enabled when enabled" do
      GC.enable
      @f.rb_gc_enable.should be_false
    end

    it "disables GC when enabled" do
      GC.enable
      @f.rb_gc_disable.should be_false
    end

    it "GC stays disabled when disabled" do
      GC.disable
      @f.rb_gc_disable.should be_true
    end
  end

  describe "rb_gc" do
    it "increases gc count" do
      gc_count = GC.count
      @f.rb_gc
      GC.count.should > gc_count
    end
  end

  describe "rb_gc_adjust_memory_usage" do
    # Just check that it does not throw, as it seems hard to observe any effect
    it "adjusts the amount of registered external memory" do
      -> {
        @f.rb_gc_adjust_memory_usage(8)
        @f.rb_gc_adjust_memory_usage(-8)
      }.should_not raise_error
    end
  end

  describe "rb_gc_register_mark_object" do
    it "can be called with an object" do
      @f.rb_gc_register_mark_object(Object.new).should be_nil
    end
  end

  describe "rb_gc_latest_gc_info" do
    it "raises a TypeError when hash or symbol not given" do
      -> { @f.rb_gc_latest_gc_info("foo") }.should raise_error(TypeError)
    end

    it "raises an ArgumentError when unknown symbol given" do
      -> { @f.rb_gc_latest_gc_info(:unknown) }.should raise_error(ArgumentError)
    end

    it "returns the populated hash when a hash is given" do
      h = {}
      @f.rb_gc_latest_gc_info(h).should == h
      h.size.should_not == 0
    end

    it "returns a value when symbol is given" do
      @f.rb_gc_latest_gc_info(:state).should be_kind_of(Symbol)
    end
  end
end
