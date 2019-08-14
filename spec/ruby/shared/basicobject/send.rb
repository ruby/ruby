module SendSpecs
end

describe :basicobject_send, shared: true do
  it "invokes the named method" do
    class SendSpecs::Foo
      def bar
        'done'
      end
    end
    SendSpecs::Foo.new.send(@method, :bar).should == 'done'
  end

  it "accepts a String method name" do
    class SendSpecs::Foo
      def bar
        'done'
      end
    end
    SendSpecs::Foo.new.send(@method, 'bar').should == 'done'
  end

  it "invokes a class method if called on a class" do
    class SendSpecs::Foo
      def self.bar
        'done'
      end
    end
    SendSpecs::Foo.send(@method, :bar).should == 'done'
  end

  it "raises a TypeError if the method name is not a string or symbol" do
    -> { SendSpecs.send(@method, nil) }.should raise_error(TypeError, /not a symbol nor a string/)
    -> { SendSpecs.send(@method, 42) }.should raise_error(TypeError, /not a symbol nor a string/)
    -> { SendSpecs.send(@method, 3.14) }.should raise_error(TypeError, /not a symbol nor a string/)
    -> { SendSpecs.send(@method, true) }.should raise_error(TypeError, /not a symbol nor a string/)
  end

  it "raises a NameError if the corresponding method can't be found" do
    class SendSpecs::Foo
      def bar
        'done'
      end
    end
    -> { SendSpecs::Foo.new.send(@method, :syegsywhwua) }.should raise_error(NameError)
  end

  it "raises a NameError if the corresponding singleton method can't be found" do
    class SendSpecs::Foo
      def self.bar
        'done'
      end
    end
    -> { SendSpecs::Foo.send(@method, :baz) }.should raise_error(NameError)
  end

  it "raises an ArgumentError if no arguments are given" do
    class SendSpecs::Foo; end
    -> { SendSpecs::Foo.new.send @method }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError if called with more arguments than available parameters" do
    class SendSpecs::Foo
      def bar; end
    end

    -> { SendSpecs::Foo.new.send(@method, :bar, :arg) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError if called with fewer arguments than required parameters" do
    class SendSpecs::Foo
      def foo(arg); end
    end

    -> { SendSpecs::Foo.new.send(@method, :foo) }.should raise_error(ArgumentError)
  end

  it "succeeds if passed an arbitrary number of arguments as a splat parameter" do
    class SendSpecs::Foo
      def baz(*args) args end
    end

    begin
      SendSpecs::Foo.new.send(@method, :baz).should == []
      SendSpecs::Foo.new.send(@method, :baz, :quux).should == [:quux]
      SendSpecs::Foo.new.send(@method, :baz, :quux, :foo).should == [:quux, :foo]
    rescue
      fail
    end
  end

  it "succeeds when passing 1 or more arguments as a required and a splat parameter" do
    class SendSpecs::Foo
      def baz(first, *rest) [first, *rest] end
    end

    SendSpecs::Foo.new.send(@method, :baz, :quux).should == [:quux]
    SendSpecs::Foo.new.send(@method, :baz, :quux, :foo).should == [:quux, :foo]
  end

  it "succeeds when passing 0 arguments to a method with one parameter with a default" do
    class SendSpecs::Foo
      def foo(first = true) first end
    end

    begin
      SendSpecs::Foo.new.send(@method, :foo).should == true
      SendSpecs::Foo.new.send(@method, :foo, :arg).should == :arg
    rescue
      fail
    end
  end

  it "has a negative arity" do
    method(@method).arity.should < 0
  end

  it "invokes module methods with super correctly" do
    m1 = Module.new { def foo(ary); ary << :m1; end; }
    m2 = Module.new { def foo(ary = []); super(ary); ary << :m2; end; }
    c2 = Class.new do
      include m1
      include m2
    end

    c2.new.send(@method, :foo, *[[]]).should == %i[m1 m2]
  end
end
