require_relative '../../spec_helper'
require 'objspace'

describe "ObjectSpace.trace_object_allocations" do
  def has_class_frame?
    Class.new {
      attr_reader :c

      def initialize
        @c = caller_locations.first.label =~ /new/
      end
    }.new.c
  end

  def obj_class_path
    has_class_frame? ? "Class" : nil
  end

  it "runs a block" do
    ScratchPad.clear
    ObjectSpace.trace_object_allocations do
      ScratchPad.record :a
    end
    ScratchPad.recorded.should == :a
  end

  it "records info for allocation_class_path" do
    ObjectSpace.trace_object_allocations do
      o = Object.new
      ObjectSpace.allocation_class_path(o).should == obj_class_path
      a = [1, 2, 3]
      ObjectSpace.allocation_class_path(a).should == nil
    end
  end

  it "records info for allocation_generation" do
    ObjectSpace.trace_object_allocations do
      o = Object.new
      ObjectSpace.allocation_generation(o).should.kind_of?(Integer)
      a = [1, 2, 3]
      ObjectSpace.allocation_generation(a).should.kind_of?(Integer)
    end
  end

  it "records info for allocation_method_id" do
    ObjectSpace.trace_object_allocations do
      o = Object.new
      ObjectSpace.allocation_method_id(o).should == (has_class_frame? ? :new : nil)
      a = [1, 2, 3]
      ObjectSpace.allocation_method_id(a).should == nil
    end
  end

  it "records info for allocation_sourcefile" do
    ObjectSpace.trace_object_allocations do
      o = Object.new
      ObjectSpace.allocation_sourcefile(o).should == __FILE__
      a = [1, 2, 3]
      ObjectSpace.allocation_sourcefile(a).should == __FILE__
    end
  end

  it "records info for allocation_sourceline" do
    ObjectSpace.trace_object_allocations do
      o = Object.new
      ObjectSpace.allocation_sourceline(o).should == __LINE__ - 1
      a = [1, 2, 3]
      ObjectSpace.allocation_sourceline(a).should == __LINE__ - 1
    end
  end

  it "can be cleared using trace_object_allocations_clear" do
    ObjectSpace.trace_object_allocations do
      o = Object.new
      ObjectSpace.allocation_class_path(o).should == obj_class_path
      ObjectSpace.trace_object_allocations_clear
      ObjectSpace.allocation_class_path(o).should be_nil
    end
  end

  it "does not clears allocation data after returning" do
    o = nil
    ObjectSpace.trace_object_allocations do
      o = Object.new
    end
    ObjectSpace.allocation_class_path(o).should == obj_class_path
  end

  it "can be used without a block using trace_object_allocations_start and _stop" do
    ObjectSpace.trace_object_allocations_start
    begin
      o = Object.new
      ObjectSpace.allocation_class_path(o).should == obj_class_path
      a = [1, 2, 3]
      ObjectSpace.allocation_class_path(a).should == nil
    ensure
      ObjectSpace.trace_object_allocations_stop
    end
  end

  it "does not clears allocation data after trace_object_allocations_stop" do
    ObjectSpace.trace_object_allocations_start
    begin
      o = Object.new
    ensure
      ObjectSpace.trace_object_allocations_stop
    end
    ObjectSpace.allocation_class_path(o).should == obj_class_path
  end

  it "can be nested" do
    ObjectSpace.trace_object_allocations do
      ObjectSpace.trace_object_allocations do
        o = Object.new
        ObjectSpace.allocation_class_path(o).should == obj_class_path
      end
    end
  end

  it "can be nested without a block using trace_object_allocations_start and _stop" do
    ObjectSpace.trace_object_allocations_start
    begin
      ObjectSpace.trace_object_allocations_start
      begin
        o = Object.new
        ObjectSpace.allocation_class_path(o).should == obj_class_path
      ensure
        ObjectSpace.trace_object_allocations_stop
      end
    ensure
      ObjectSpace.trace_object_allocations_stop
    end
  end

  it "can be nested with more _stop than _start" do
    ObjectSpace.trace_object_allocations_start
    begin
      o = Object.new
      ObjectSpace.allocation_class_path(o).should == obj_class_path
      ObjectSpace.trace_object_allocations_stop
    ensure
      ObjectSpace.trace_object_allocations_stop
    end
  end

  it "returns nil for class_path, generation, method_id, sourcefile, and sourceline for immutable objects" do
    ObjectSpace.trace_object_allocations_start
    begin
      one = nil
      two = 42
      three = :foo
      [one, two, three].each do |i|
        ObjectSpace.allocation_class_path(i).should == nil
        ObjectSpace.allocation_generation(i).should == nil
        ObjectSpace.allocation_method_id(i).should == nil
        ObjectSpace.allocation_sourcefile(i).should == nil
        ObjectSpace.allocation_sourceline(i).should == nil
      end
    ensure
      ObjectSpace.trace_object_allocations_stop
    end
  end
end
