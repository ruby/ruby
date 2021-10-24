require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/dup_clone'

describe "Kernel#clone" do
  it_behaves_like :kernel_dup_clone, :clone

  before :each do
    ScratchPad.clear
    @obj = KernelSpecs::Duplicate.new 1, :a
  end

  it "calls #initialize_copy on the new instance" do
    clone = @obj.clone
    ScratchPad.recorded.should_not == @obj.object_id
    ScratchPad.recorded.should == clone.object_id
  end

  it "uses the internal allocator and does not call #allocate" do
    klass = Class.new
    instance = klass.new

    def klass.allocate
      raise "allocate should not be called"
    end

    clone = instance.clone
    clone.class.should equal klass
  end

  describe "with no arguments" do
    it "copies frozen state from the original" do
      o2 = @obj.clone
      @obj.freeze
      o3 = @obj.clone

      o2.should_not.frozen?
      o3.should.frozen?
    end

    it 'copies frozen?' do
      o = ''.freeze.clone
      o.frozen?.should be_true
    end
  end

  describe "with freeze: true" do
    it 'makes a frozen copy if the original is frozen' do
      @obj.freeze
      @obj.clone(freeze: true).should.frozen?
    end

    ruby_version_is ''...'3.0' do
      it 'does not freeze the copy even if the original is not frozen' do
        @obj.clone(freeze: true).should_not.frozen?
      end

      it "calls #initialize_clone with no kwargs" do
        obj = KernelSpecs::CloneFreeze.new
        obj.clone(freeze: true)
        ScratchPad.recorded.should == [obj, {}]
      end
    end

    ruby_version_is '3.0' do
      it 'freezes the copy even if the original was not frozen' do
        @obj.clone(freeze: true).should.frozen?
      end

      it "calls #initialize_clone with kwargs freeze: true" do
        obj = KernelSpecs::CloneFreeze.new
        obj.clone(freeze: true)
        ScratchPad.recorded.should == [obj, { freeze: true }]
      end

      it "calls #initialize_clone with kwargs freeze: true even if #initialize_clone only takes a single argument" do
        obj = KernelSpecs::Clone.new
        -> { obj.clone(freeze: true) }.should raise_error(ArgumentError, 'wrong number of arguments (given 2, expected 1)')
      end
    end
  end

  describe "with freeze: false" do
    it 'does not freeze the copy if the original is frozen' do
      @obj.freeze
      @obj.clone(freeze: false).should_not.frozen?
    end

    it 'does not freeze the copy if the original is not frozen' do
      @obj.clone(freeze: false).should_not.frozen?
    end

    ruby_version_is ''...'3.0' do
      it "calls #initialize_clone with no kwargs" do
        obj = KernelSpecs::CloneFreeze.new
        obj.clone(freeze: false)
        ScratchPad.recorded.should == [obj, {}]
      end
    end

    ruby_version_is '3.0' do
      it "calls #initialize_clone with kwargs freeze: false" do
        obj = KernelSpecs::CloneFreeze.new
        obj.clone(freeze: false)
        ScratchPad.recorded.should == [obj, { freeze: false }]
      end

      it "calls #initialize_clone with kwargs freeze: false even if #initialize_clone only takes a single argument" do
        obj = KernelSpecs::Clone.new
        -> { obj.clone(freeze: false) }.should raise_error(ArgumentError, 'wrong number of arguments (given 2, expected 1)')
      end
    end
  end

  it "copies instance variables" do
    clone = @obj.clone
    clone.one.should == 1
    clone.two.should == :a
  end

  it "copies singleton methods" do
    def @obj.special() :the_one end
    clone = @obj.clone
    clone.special.should == :the_one
  end

  it "copies modules included in the singleton class" do
    class << @obj
      include KernelSpecs::DuplicateM
    end

    clone = @obj.clone
    clone.repr.should == "KernelSpecs::Duplicate"
  end

  it "copies constants defined in the singleton class" do
    class << @obj
      CLONE = :clone
    end

    clone = @obj.clone
    class << clone
      CLONE.should == :clone
    end
  end

  it "replaces a singleton object's metaclass with a new copy with the same superclass" do
    cls = Class.new do
      def bar
        ['a']
      end
    end

    object = cls.new
    object.define_singleton_method(:bar) do
      ['b', *super()]
    end
    object.bar.should == ['b', 'a']

    cloned = object.clone

    cloned.singleton_methods.should == [:bar]

    # bar should replace previous one
    cloned.define_singleton_method(:bar) do
      ['c', *super()]
    end
    cloned.bar.should == ['c', 'a']

    # bar should be removed and call through to superclass
    cloned.singleton_class.class_eval do
      remove_method :bar
    end

    cloned.bar.should == ['a']
  end

  ruby_version_is ''...'2.7' do
    it 'copies tainted?' do
      o = ''.taint.clone
      o.tainted?.should be_true
    end
  end
end
