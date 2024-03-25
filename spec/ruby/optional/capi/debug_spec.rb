require_relative 'spec_helper'

load_extension('debug')

describe "C-API Debug function" do
  before :each do
    @o = CApiDebugSpecs.new
  end

  describe "rb_debug_inspector_open" do
    it "creates a debug context and calls the given callback" do
      @o.rb_debug_inspector_open(42).should be_kind_of(Array)
      @o.debug_spec_callback_data.should == 42
    end
  end

  describe "rb_debug_inspector_frame_self_get" do
    it "returns self" do
      @o.rb_debug_inspector_frame_self_get(0).should == @o
      @o.rb_debug_inspector_frame_self_get(1).should == self
    end
  end

  describe "rb_debug_inspector_frame_class_get" do
    it "returns the frame class" do
      @o.rb_debug_inspector_frame_class_get(0).should == CApiDebugSpecs
    end
  end

  describe "rb_debug_inspector_frame_binding_get" do
    it "returns the current binding" do
      a = "test"
      b = @o.rb_debug_inspector_frame_binding_get(1)
      b.should be_an_instance_of(Binding)
      b.local_variable_get(:a).should == "test"
    end

    it "matches the locations in rb_debug_inspector_backtrace_locations" do
      frames = @o.rb_debug_inspector_open(42)
      frames.each do |_s, _klass, binding, _iseq, backtrace_location|
        if binding
          binding.source_location.should == [backtrace_location.path, backtrace_location.lineno]
          method_name = binding.eval('__method__')
          if method_name
            method_name.should == backtrace_location.base_label.to_sym
          end
        end
      end
    end
  end

  describe "rb_debug_inspector_frame_iseq_get" do
    it "returns an InstructionSequence" do
      if defined?(RubyVM::InstructionSequence)
        @o.rb_debug_inspector_frame_iseq_get(1).should be_an_instance_of(RubyVM::InstructionSequence)
      else
        @o.rb_debug_inspector_frame_iseq_get(1).should == nil
      end
    end
  end

  describe "rb_debug_inspector_backtrace_locations" do
    it "returns an array of Thread::Backtrace::Location" do
      bts = @o.rb_debug_inspector_backtrace_locations
      bts.should_not.empty?
      bts.each { |bt| bt.should be_kind_of(Thread::Backtrace::Location) }
      location = "#{__FILE__}:#{__LINE__ - 3}"
      bts[1].to_s.should include(location)
    end
  end
end
