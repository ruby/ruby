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
      o = Object.new
      o.instance_variable_set(:@a, +"a")
      o.instance_variable_set(:@b, [+"b"])
      o.deep_freeze
      o.should.frozen?
      o.instance_variable_get(:@a).should.frozen?
      o.instance_variable_get(:@b).should.frozen?
      o.instance_variable_get(:@b)[0].should.frozen?
    end

    it "freezes an Exception and its message" do
      e = RuntimeError.new(+"message")
      e.deep_freeze
      e.should.frozen?
      e.message.should.frozen?
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

    describe "with classes and modules" do
      it "does not freeze a class or module which is the receiver" do
        klass = Class.new
        klass.deep_freeze.should.equal?(klass)
        klass.should_not.frozen?

        mod = Module.new
        mod.deep_freeze.should.equal?(mod)
        mod.should_not.frozen?
      end

      it "does not freeze a class or module which is reachable" do
        klass = Class.new
        mod = Module.new
        h = { klass => mod }
        h.deep_freeze
        h.should.frozen?
        klass.should_not.frozen?
        mod.should_not.frozen?
      end

      it "does not freeze the constants or instance variables of a reachable class" do
        klass = Class.new
        klass.const_set(:CONST, +"const")
        klass.instance_variable_set(:@ivar, +"ivar")
        [klass].deep_freeze
        klass::CONST.should_not.frozen?
        klass.instance_variable_get(:@ivar).should_not.frozen?
      end

      it "does not freeze the class of the receiver or its ancestors" do
        mod = Module.new
        klass = Class.new { include mod }
        klass.new.deep_freeze
        klass.should_not.frozen?
        mod.should_not.frozen?
        Object.should_not.frozen?
      end

      it "does not freeze the class of a Set" do
        klass = Class.new(Set)
        klass[Object.new].deep_freeze
        klass.should_not.frozen?
      end

      it "freezes the singleton class of the receiver, like #freeze" do
        o = Object.new
        o.deep_freeze
        o.singleton_class.should.frozen?
      end
    end

    describe "with core classes implemented with internal references" do
      it "freezes a Proc but not its self or captured variables" do
        o = Object.new
        pr = o.instance_eval { proc { } }
        pr.deep_freeze
        pr.should.frozen?
        o.should_not.frozen?

        str = +"str"
        pr = -> { str }
        pr.deep_freeze
        pr.should.frozen?
        str.should_not.frozen?
        self.should_not.frozen?
      end

      it "freezes a Method but not its receiver" do
        str = +"str"
        m = str.method(:upcase)
        m.deep_freeze
        m.should.frozen?
        str.should_not.frozen?
      end

      it "freezes an UnboundMethod" do
        m = String.instance_method(:upcase)
        m.deep_freeze
        m.should.frozen?
        String.should_not.frozen?
      end

      it "freezes a Binding but not its self or local variables" do
        o = Object.new
        b = o.instance_eval { binding }
        b.deep_freeze
        b.should.frozen?
        o.should_not.frozen?

        str = +"str"
        b = binding
        b.deep_freeze
        b.should.frozen?
        str.should_not.frozen?
        self.should_not.frozen?
      end

      it "freezes an Enumerator and the object it iterates" do
        a = [Object.new]
        e = a.each
        e.deep_freeze
        e.should.frozen?
        a.should.frozen?
        a[0].should.frozen?
      end

      it "freezes a Thread but not the objects on its stack" do
        str = +"str"
        t = Thread.new do
          Thread.current.deep_freeze
          str
        end
        t.value.should.equal?(str)
        t.should.frozen?
        self.should_not.frozen?
        str.should_not.frozen?
      end

      it "freezes a Fiber but not the objects on its stack" do
        str = +"str"
        f = Fiber.new { Fiber.yield; str }
        f.resume
        f.deep_freeze
        f.should.frozen?
        str.should_not.frozen?
        self.should_not.frozen?
        f.resume.should.equal?(str)
      end

      it "freezes an Enumerator with an active external iteration but not the objects on the stack of its Fiber" do
        str = +"str"
        e = Enumerator.new { |y| y << 1; y << str }
        e.next.should == 1
        e.deep_freeze
        e.should.frozen?
        str.should_not.frozen?
        self.should_not.frozen?
      end

      it "freezes a Mutex and a ConditionVariable" do
        m = Thread::Mutex.new
        m.deep_freeze
        m.should.frozen?
        cv = Thread::ConditionVariable.new
        cv.deep_freeze
        cv.should.frozen?
      end

      it "raises TypeError for a Thread::Queue, like Thread::Queue#freeze" do
        q = Thread::Queue.new
        -> { [q].deep_freeze }.should raise_error(TypeError)
        q = Thread::SizedQueue.new(1)
        -> { [q].deep_freeze }.should raise_error(TypeError)
      end

      it "freezes a Time" do
        t = Time.now
        t.deep_freeze
        t.should.frozen?
      end

      it "freezes a Random" do
        r = Random.new(42)
        r.deep_freeze
        r.should.frozen?
        r.rand(10).should == Random.new(42).rand(10)
      end

      it "freezes a Dir" do
        d = Dir.new(".")
        d.deep_freeze
        d.should.frozen?
      end

      it "freezes an IO and its instance variables" do
        IO.pipe do |r, w|
          str = +"str"
          r.instance_variable_set(:@ivar, str)
          r.deep_freeze
          r.should.frozen?
          str.should.frozen?
        end
      end
    end

    describe "calling #freeze" do
      it "calls #freeze on each object" do
        o = KernelSpecs::DeepFreezeHook.new
        before = KernelSpecs::DeepFreezeHook.freeze_calls
        [o].deep_freeze
        o.should.frozen?
        KernelSpecs::DeepFreezeHook.freeze_calls.should == before + 1
      end

      it "freezes instance variables set by #freeze" do
        klass = Class.new do
          attr_reader :cache

          def initialize(value)
            @value = value
          end

          def freeze
            @cache = @value.upcase
            super
          end
        end
        o = klass.new(+"a")
        o.deep_freeze
        o.should.frozen?
        o.cache.should == "A"
        o.cache.should.frozen?
      end

      it "allows #freeze to call #object_id on an object being traversed" do
        parent = Object.new
        child = Class.new do
          define_method(:freeze) do
            parent.object_id
            super()
          end
        end.new
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
        o = Class.new do
          def freeze
            self
          end
        end.new
        -> { [o].deep_freeze }.should raise_error(RuntimeError, "#freeze does not freeze object correctly")
      end

      it "propagates exceptions raised by #freeze" do
        o = Class.new do
          def freeze
            raise "boom"
          end
        end.new
        -> { [o].deep_freeze }.should raise_error(RuntimeError, "boom")
      end
    end
  end
end
