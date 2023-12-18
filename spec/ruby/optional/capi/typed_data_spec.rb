require_relative 'spec_helper'
require 'objspace'

load_extension("typed_data")

describe "CApiAllocTypedSpecs (a class with an alloc func defined)" do
  it "calls the alloc func" do
    @s = CApiAllocTypedSpecs.new
    @s.typed_wrapped_data.should == 42 # not defined in initialize
  end

  it "uses the specified memsize function for ObjectSpace.memsize" do
    @s = CApiAllocTypedSpecs.new
    # The defined memsize function for the type should return 42 as
    # the size, and this should be added to the size of the object as
    # known by Ruby.
    ObjectSpace.memsize_of(@s).should > 42
  end
end

describe "CApiWrappedTypedStruct" do
  before :each do
    @s = CApiWrappedTypedStructSpecs.new
  end

  it "wraps and unwraps data" do
    a = @s.typed_wrap_struct(1024)
    @s.typed_get_struct(a).should == 1024
  end

  it "throws an exception for a wrong type" do
    a = @s.typed_wrap_struct(1024)
    -> { @s.typed_get_struct_other(a) }.should raise_error(TypeError)
  end

  it "unwraps data for a parent type" do
    a = @s.typed_wrap_struct(1024)
    @s.typed_get_struct_parent(a).should == 1024
  end

  describe "RTYPEDATA" do
    it "returns the struct data" do
      a = @s.typed_wrap_struct(1024)
      @s.typed_get_struct_rdata(a).should == 1024
    end

    it "can be used to change the wrapped struct" do
      a = @s.typed_wrap_struct(1024)
      @s.typed_change_struct(a, 100)
      @s.typed_get_struct(a).should == 100
    end
  end

  describe "DATA_PTR" do
    it "returns the struct data" do
      a = @s.typed_wrap_struct(1024)
      @s.typed_get_struct_data_ptr(a).should == 1024
    end
  end

  describe "rb_check_type" do
    it "raises an exception when checking typed data objects" do
      -> {
        a = @s.typed_wrap_struct(1024)
        @s.rb_check_type(a, a)
      }.should raise_error(TypeError) { |e|
        e.message.should == 'wrong argument type Object (expected Data)'
      }
    end
  end

  describe "rb_check_typeddata" do
    it "returns data pointer when the struct has the given type" do
      a = @s.typed_wrap_struct(1024)
      @s.rb_check_typeddata_same_type(a).should == true
    end

    it "returns data pointer when the parent struct has the given type" do
      a = @s.typed_wrap_struct(1024)
      @s.rb_check_typeddata_same_type_parent(a).should == true
    end

    it "raises an error for different types" do
      a = @s.typed_wrap_struct(1024)
      -> { @s.rb_check_typeddata_different_type(a) }.should raise_error(TypeError)
    end
  end

  describe "RTYPEDDATA_P" do
    it "returns true for a typed data" do
      a = @s.typed_wrap_struct(1024)
      @s.RTYPEDDATA_P(a).should == true
    end

    it "returns false for an untyped data object" do
      a = @s.untyped_wrap_struct(1024)
      @s.RTYPEDDATA_P(a).should == false
    end
  end
end
