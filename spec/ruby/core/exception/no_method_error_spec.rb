require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "NoMethodError.new" do
  it "allows passing method args" do
    NoMethodError.new("msg", "name", ["args"]).args.should == ["args"]
  end

  it "does not require a name" do
    NoMethodError.new("msg").message.should == "msg"
  end

  it "accepts a :receiver keyword argument" do
    receiver = mock("receiver")

    error = NoMethodError.new("msg", :name, receiver: receiver)

    error.receiver.should == receiver
    error.name.should == :name
  end
end

describe "NoMethodError#args" do
  it "returns an empty array if the caller method had no arguments" do
    begin
      NoMethodErrorSpecs::NoMethodErrorB.new.foo
    rescue Exception => e
      e.args.should == []
    end
  end

  it "returns an array with the same elements as passed to the method" do
    begin
      a = NoMethodErrorSpecs::NoMethodErrorA.new
      NoMethodErrorSpecs::NoMethodErrorB.new.foo(1,a)
    rescue Exception => e
      e.args.should == [1,a]
      e.args[1].should equal a
    end
  end
end

describe "NoMethodError#message" do
  it "for an undefined method match /undefined method/" do
    begin
      NoMethodErrorSpecs::NoMethodErrorD.new.foo
    rescue Exception => e
      e.should be_kind_of(NoMethodError)
    end
  end

  it "for an protected method match /protected method/" do
    begin
      NoMethodErrorSpecs::NoMethodErrorC.new.a_protected_method
    rescue Exception => e
      e.should be_kind_of(NoMethodError)
    end
  end

  it "for private method match /private method/" do
    begin
      NoMethodErrorSpecs::NoMethodErrorC.new.a_private_method
    rescue Exception => e
      e.should be_kind_of(NoMethodError)
      e.message.lines[0].should =~ /private method [`']a_private_method' called for /
    end
  end

  ruby_version_is ""..."3.3" do
    it "calls #inspect when calling Exception#message" do
      ScratchPad.record []
      test_class = Class.new do
        def inspect
          ScratchPad << :inspect_called
          "<inspect>"
        end
      end
      instance = test_class.new

      begin
        instance.bar
      rescue NoMethodError => error
        error.message.should =~ /\Aundefined method [`']bar' for <inspect>:#<Class:0x\h+>$/
        ScratchPad.recorded.should == [:inspect_called]
      end
    end

    it "fallbacks to a simpler representation of the receiver when receiver.inspect raises an exception" do
      test_class = Class.new do
        def inspect
          raise NoMethodErrorSpecs::InstanceException
        end
      end
      instance = test_class.new

      begin
        instance.bar
      rescue NoMethodError => error
        message = error.message
        message.should =~ /undefined method.+\bbar\b/
        message.should include test_class.inspect
      end
    end

    it "uses #name to display the receiver if it is a class" do
      klass = Class.new { def self.name; "MyClass"; end }

      begin
        klass.foo
      rescue NoMethodError => error
        error.message.should =~ /\Aundefined method [`']foo' for MyClass:Class$/
      end
    end

    it "uses #name to display the receiver if it is a module" do
      mod = Module.new { def self.name; "MyModule"; end }

      begin
        mod.foo
      rescue NoMethodError => error
        error.message.should =~ /\Aundefined method [`']foo' for MyModule:Module$/
      end
    end
  end

  ruby_version_is "3.3" do
    it "uses a literal name when receiver is nil" do
      begin
        nil.foo
      rescue NoMethodError => error
        error.message.should =~ /\Aundefined method [`']foo' for nil\Z/
      end
    end

    it "uses a literal name when receiver is true" do
      begin
        true.foo
      rescue NoMethodError => error
        error.message.should =~ /\Aundefined method [`']foo' for true\Z/
      end
    end

    it "uses a literal name when receiver is false" do
      begin
        false.foo
      rescue NoMethodError => error
        error.message.should =~ /\Aundefined method [`']foo' for false\Z/
      end
    end

    it "uses #name when receiver is a class" do
      klass = Class.new { def self.name; "MyClass"; end }

      begin
        klass.foo
      rescue NoMethodError => error
        error.message.should =~ /\Aundefined method [`']foo' for class MyClass\Z/
      end
    end

    it "uses class' string representation when receiver is an anonymous class" do
      klass = Class.new

      begin
        klass.foo
      rescue NoMethodError => error
        error.message.should =~ /\Aundefined method [`']foo' for class #<Class:0x\h+>\Z/
      end
    end

    it "uses class' string representation when receiver is a singleton class" do
      obj = Object.new
      singleton_class = obj.singleton_class

      begin
        singleton_class.foo
      rescue NoMethodError => error
        error.message.should =~ /\Aundefined method [`']foo' for class #<Class:#<Object:0x\h+>>\Z/
      end
    end

    it "uses #name when receiver is a module" do
      mod = Module.new { def self.name; "MyModule"; end }

      begin
        mod.foo
      rescue NoMethodError => error
        error.message.should =~ /\Aundefined method [`']foo' for module MyModule\Z/
      end
    end

    it "uses module's string representation when receiver is an anonymous module" do
      m = Module.new

      begin
        m.foo
      rescue NoMethodError => error
        error.message.should =~ /\Aundefined method [`']foo' for module #<Module:0x\h+>\Z/
      end
    end

    it "uses class #name when receiver is an ordinary object" do
      klass = Class.new { def self.name; "MyClass"; end }
      instance = klass.new

      begin
        instance.bar
      rescue NoMethodError => error
        error.message.should =~ /\Aundefined method [`']bar' for an instance of MyClass\Z/
      end
    end

    it "uses class string representation when receiver is an instance of anonymous class" do
      klass = Class.new
      instance = klass.new

      begin
        instance.bar
      rescue NoMethodError => error
        error.message.should =~ /\Aundefined method [`']bar' for an instance of #<Class:0x\h+>\Z/
      end
    end

    it "uses class name when receiver has a singleton class" do
      instance = NoMethodErrorSpecs::NoMethodErrorA.new
      def instance.foo; end

      begin
        instance.bar
      rescue NoMethodError => error
        error.message.should =~ /\Aundefined method [`']bar' for #<NoMethodErrorSpecs::NoMethodErrorA:0x\h+>\Z/
      end
    end

    it "does not call #inspect when calling Exception#message" do
      ScratchPad.record []
      test_class = Class.new do
        def inspect
          ScratchPad << :inspect_called
          "<inspect>"
        end
      end
      instance = test_class.new

      begin
        instance.bar
      rescue NoMethodError => error
        error.message.should =~ /\Aundefined method [`']bar' for an instance of #<Class:0x\h+>\Z/
        ScratchPad.recorded.should == []
      end
    end

    it "does not truncate long class names" do
      class_name = 'ExceptionSpecs::A' + 'a'*100

      begin
        eval <<~RUBY
          class #{class_name}
          end

          obj = #{class_name}.new
          obj.foo
        RUBY
      rescue NoMethodError => error
        error.message.should =~ /\Aundefined method [`']foo' for an instance of #{class_name}\Z/
      end
    end
  end
end

describe "NoMethodError#dup" do
  it "copies the name, arguments and receiver" do
    begin
      receiver = Object.new
      receiver.foo(:one, :two)
    rescue NoMethodError => nme
      no_method_error_dup = nme.dup
      no_method_error_dup.name.should == :foo
      no_method_error_dup.receiver.should == receiver
      no_method_error_dup.args.should == [:one, :two]
    end
  end
end
