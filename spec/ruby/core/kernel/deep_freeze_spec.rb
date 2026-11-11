require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is "4.1" do
  describe "Kernel#deep_freeze" do
    it "returns self" do
      o = Object.new
      o.deep_freeze.should.equal?(o)
      nil.deep_freeze.should == nil
      true.deep_freeze.should == true
      1.deep_freeze.should == 1
      :sym.deep_freeze.should == :sym
    end

    it "freezes self" do
      o = Object.new
      o.deep_freeze
      o.should.frozen?
    end

    it "freezes Array elements recursively" do
      a = [+"a", [+"b", [+"c"]]]
      a.deep_freeze
      a.should.frozen?
      a[0].should.frozen?
      a[1].should.frozen?
      a[1][0].should.frozen?
      a[1][1].should.frozen?
      a[1][1][0].should.frozen?
    end

    it "freezes Hash keys and values recursively" do
      k = Object.new
      v = { x: +"x" }
      h = { k => v }
      h.deep_freeze
      h.should.frozen?
      k.should.frozen?
      v.should.frozen?
      v[:x].should.frozen?
    end

    it "freezes the Hash default proc" do
      h = Hash.new { |hash, k| k }
      h.deep_freeze
      h.default_proc.should.frozen?
    end

    it "freezes Struct members recursively" do
      s = Struct.new(:a).new(+"a")
      s.deep_freeze
      s.should.frozen?
      s.a.should.frozen?
    end

    it "freezes Data members recursively" do
      d = Data.define(:a).new(a: +"a")
      d.deep_freeze
      d.should.frozen?
      d.a.should.frozen?
    end

    it "freezes Set elements recursively" do
      e = Object.new
      s = Set[e]
      s.deep_freeze
      s.should.frozen?
      e.should.frozen?
    end

    it "freezes Range bounds recursively" do
      r = (+"a")..(+"z")
      r.deep_freeze
      r.should.frozen?
      r.begin.should.frozen?
      r.end.should.frozen?
    end

    it "freezes instance variables recursively" do
      o = KernelSpecs::DeepFreezeIvars.new(+"a", [+"b"])
      o.deep_freeze
      o.should.frozen?
      o.a.should.frozen?
      o.b.should.frozen?
      o.b[0].should.frozen?
    end

    it "handles cyclic references" do
      a = []
      a << a
      h = { a: a }
      a << h
      a.deep_freeze
      a.should.frozen?
      h.should.frozen?
    end

    it "does not freeze the class of the receiver" do
      klass = Class.new
      klass.new.deep_freeze
      klass.should_not.frozen?
    end

    it "does not freeze the modules included in the class of the receiver" do
      mod = Module.new
      Class.new { include mod }.new.deep_freeze
      mod.should_not.frozen?
    end

    it "does not freeze the class of a Set" do
      klass = Class.new(Set)
      klass[Object.new].deep_freeze
      klass.should_not.frozen?
    end

    it "freezes the class of a Set if it is an element of the Set" do
      klass = Class.new(Set)
      klass[klass].deep_freeze
      klass.should.frozen?
    end

    it "freezes a class or module which is the receiver but does not traverse it" do
      klass = Class.new
      klass.const_set(:CONST, +"const")
      klass.instance_variable_set(:@ivar, +"ivar")
      klass.deep_freeze
      klass.should.frozen?
      klass::CONST.should_not.frozen?
      klass.instance_variable_get(:@ivar).should_not.frozen?
      Object.should_not.frozen?

      mod = Module.new
      mod.const_set(:CONST, +"const")
      mod.deep_freeze
      mod.should.frozen?
      mod::CONST.should_not.frozen?
    end

    it "freezes a class or module which is reachable but does not traverse it" do
      klass = Class.new
      klass.const_set(:CONST, +"const")
      [klass].deep_freeze
      klass.should.frozen?
      klass::CONST.should_not.frozen?
    end

    it "does not traverse Thread, Fiber and Proc objects" do
      str = +"str"
      obj = Object.new

      th = Thread.new { str }
      th.deep_freeze
      th.should.frozen?
      str.should_not.frozen?
      th.value.should.equal?(str)

      fiber = Fiber.new { str }
      fiber.deep_freeze
      fiber.should.frozen?
      str.should_not.frozen?
      fiber.resume.should.equal?(str)

      pr = proc { [str, obj] }
      pr.deep_freeze
      pr.should.frozen?
      str.should_not.frozen?
      obj.should_not.frozen?
    end

    it "does not traverse Method objects" do
      str = +"str"
      m = str.method(:upcase)
      m.deep_freeze
      m.should.frozen?
      str.should_not.frozen?
    end

    it "does not traverse IO objects" do
      IO.pipe do |r, w|
        str = +"str"
        r.instance_variable_set(:@ivar, str)
        r.deep_freeze
        r.should.frozen?
        str.should_not.frozen?
      end
    end

    it "calls #freeze on each object" do
      o = KernelSpecs::DeepFreezeHook.new
      before = KernelSpecs::DeepFreezeHook.freeze_calls
      [o].deep_freeze
      o.should.frozen?
      KernelSpecs::DeepFreezeHook.freeze_calls.should == before + 1
    end

    it "freezes instance variables set by #freeze" do
      o = KernelSpecs::DeepFreezeCache.new(+"a")
      o.deep_freeze
      o.should.frozen?
      o.cache.should == "A"
      o.cache.should.frozen?
    end

    it "allows #freeze to call #object_id on an object being traversed" do
      parent = Object.new
      child = KernelSpecs::DeepFreezeObjectId.new(parent)
      parent.instance_variable_set(:@child, child)
      parent.deep_freeze
      parent.should.frozen?
      child.should.frozen?
    end

    it "does not call #freeze on already frozen objects" do
      o = KernelSpecs::DeepFreezeHook.new.freeze
      before = KernelSpecs::DeepFreezeHook.freeze_calls
      [o].deep_freeze
      KernelSpecs::DeepFreezeHook.freeze_calls.should == before
    end

    it "traverses already frozen objects" do
      inner = +"inner"
      a = [inner].freeze
      a.deep_freeze
      inner.should.frozen?
    end

    it "raises RuntimeError if #freeze does not freeze the object" do
      o = KernelSpecs::DeepFreezeNoFreeze.new
      -> { [o].deep_freeze }.should raise_error(RuntimeError, "#freeze does not freeze object correctly")
    end

    it "propagates exceptions raised by #freeze" do
      o = KernelSpecs::DeepFreezeRaise.new
      -> { [o].deep_freeze }.should raise_error(RuntimeError, "boom")
    end
  end
end
