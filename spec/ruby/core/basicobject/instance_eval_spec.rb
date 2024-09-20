require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "BasicObject#instance_eval" do
  before :each do
    ScratchPad.clear
  end

  it "is a public instance method" do
    BasicObject.should have_public_instance_method(:instance_eval)
  end

  it "sets self to the receiver in the context of the passed block" do
    a = BasicObject.new
    a.instance_eval { self }.equal?(a).should be_true
  end

  it "evaluates strings" do
    a = BasicObject.new
    a.instance_eval('self').equal?(a).should be_true
  end

  it "raises an ArgumentError when no arguments and no block are given" do
    -> { "hola".instance_eval }.should raise_error(ArgumentError, "wrong number of arguments (given 0, expected 1..3)")
  end

  it "raises an ArgumentError when a block and normal arguments are given" do
    -> { "hola".instance_eval(4, 5) {|a,b| a + b } }.should raise_error(ArgumentError, "wrong number of arguments (given 2, expected 0)")
  end

  it "raises an ArgumentError when more than 3 arguments are given" do
    -> {
      "hola".instance_eval("1 + 1", "some file", 0, "bogus")
    }.should raise_error(ArgumentError, "wrong number of arguments (given 4, expected 1..3)")
  end

  it "yields the object to the block" do
    "hola".instance_eval {|o| ScratchPad.record o }
    ScratchPad.recorded.should == "hola"
  end

  it "returns the result of the block" do
    "hola".instance_eval { :result }.should == :result
  end

  it "only binds the eval to the receiver" do
    f = Object.new
    f.instance_eval do
      def foo
        1
      end
    end
    f.foo.should == 1
    -> { Object.new.foo }.should raise_error(NoMethodError)
  end

  it "preserves self in the original block when passed a block argument" do
    prc = proc { self }

    old_self = prc.call

    new_self = Object.new
    new_self.instance_eval(&prc).should == new_self

    prc.call.should == old_self
  end

  # TODO: This should probably be replaced with a "should behave like" that uses
  # the many scoping/binding specs from kernel/eval_spec, since most of those
  # behaviors are the same for instance_eval. See also module_eval/class_eval.

  it "binds self to the receiver" do
    s = "hola"
    (s == s.instance_eval { self }).should be_true
    o = mock('o')
    (o == o.instance_eval("self")).should be_true
  end

  it "executes in the context of the receiver" do
    "Ruby-fu".instance_eval { size }.should == 7
    "hola".instance_eval("size").should == 4
    Object.class_eval { "hola".instance_eval("to_s") }.should == "hola"
    Object.class_eval { "Ruby-fu".instance_eval{ to_s } }.should == "Ruby-fu"

  end

  ruby_version_is "3.3" do
    it "uses the caller location as default location" do
      f = Object.new
      f.instance_eval("[__FILE__, __LINE__]").should == ["(eval at #{__FILE__}:#{__LINE__})", 1]
    end
  end

  it "has access to receiver's instance variables" do
    BasicObjectSpecs::IVars.new.instance_eval { @secret }.should == 99
    BasicObjectSpecs::IVars.new.instance_eval("@secret").should == 99
  end

  it "raises TypeError for frozen objects when tries to set receiver's instance variables" do
    -> { nil.instance_eval { @foo = 42 } }.should raise_error(FrozenError, "can't modify frozen NilClass: nil")
    -> { true.instance_eval { @foo = 42 } }.should raise_error(FrozenError, "can't modify frozen TrueClass: true")
    -> { false.instance_eval { @foo = 42 } }.should raise_error(FrozenError, "can't modify frozen FalseClass: false")
    -> { 1.instance_eval { @foo = 42 } }.should raise_error(FrozenError, "can't modify frozen Integer: 1")
    -> { :symbol.instance_eval { @foo = 42 } }.should raise_error(FrozenError, "can't modify frozen Symbol: :symbol")

    obj = Object.new
    obj.freeze
    -> { obj.instance_eval { @foo = 42 } }.should raise_error(FrozenError)
  end

  it "treats block-local variables as local to the block" do
    prc = instance_eval <<-CODE
      proc do |x, prc|
        if x
          n = 2
        else
          n = 1
          prc.call(true, prc)
          n
        end
      end
    CODE

    prc.call(false, prc).should == 1
  end

  it "makes the receiver metaclass the scoped class when used with a string" do
    obj = Object.new
    obj.instance_eval %{
      class B; end
      B
    }
    obj.singleton_class.const_get(:B).should be_an_instance_of(Class)
  end

  describe "constants lookup when a String given" do
    it "looks in the receiver singleton class first" do
      receiver = BasicObjectSpecs::InstEval::Constants::ConstantInReceiverSingletonClass::ReceiverScope::Receiver.new
      caller = BasicObjectSpecs::InstEval::Constants::ConstantInReceiverSingletonClass::CallerScope::Caller.new

      caller.get_constant_with_string(receiver).should == :singleton_class
    end

    ruby_version_is ""..."3.1" do
      it "looks in the caller scope next" do
        receiver = BasicObjectSpecs::InstEval::Constants::ConstantInReceiverClass::ReceiverScope::Receiver.new
        caller = BasicObjectSpecs::InstEval::Constants::ConstantInReceiverClass::CallerScope::Caller.new

        caller.get_constant_with_string(receiver).should == :Caller
      end
    end

    ruby_version_is "3.1" do
      it "looks in the receiver class next" do
        receiver = BasicObjectSpecs::InstEval::Constants::ConstantInReceiverClass::ReceiverScope::Receiver.new
        caller = BasicObjectSpecs::InstEval::Constants::ConstantInReceiverClass::CallerScope::Caller.new

        caller.get_constant_with_string(receiver).should == :Receiver
      end
    end

    it "looks in the caller class next" do
      receiver = BasicObjectSpecs::InstEval::Constants::ConstantInCallerClass::ReceiverScope::Receiver.new
      caller = BasicObjectSpecs::InstEval::Constants::ConstantInCallerClass::CallerScope::Caller.new

      caller.get_constant_with_string(receiver).should == :Caller
    end

    it "looks in the caller outer scopes next" do
      receiver = BasicObjectSpecs::InstEval::Constants::ConstantInCallerOuterScopes::ReceiverScope::Receiver.new
      caller = BasicObjectSpecs::InstEval::Constants::ConstantInCallerOuterScopes::CallerScope::Caller.new

      caller.get_constant_with_string(receiver).should == :CallerScope
    end

    it "looks in the receiver class hierarchy next" do
      receiver = BasicObjectSpecs::InstEval::Constants::ConstantInReceiverParentClass::ReceiverScope::Receiver.new
      caller = BasicObjectSpecs::InstEval::Constants::ConstantInReceiverParentClass::CallerScope::Caller.new

      caller.get_constant_with_string(receiver).should == :ReceiverParent
    end
  end

  it "doesn't get constants in the receiver if a block given" do
    BasicObjectSpecs::InstEvalOuter::Inner::X_BY_BLOCK.should be_nil
  end

  it "raises a TypeError when defining methods on an immediate" do
    -> do
      1.instance_eval { def foo; end }
    end.should raise_error(TypeError)
    -> do
      :foo.instance_eval { def foo; end }
    end.should raise_error(TypeError)
  end

  describe "class variables lookup" do
    it "gets class variables in the caller class when called with a String" do
      receiver = BasicObjectSpecs::InstEval::CVar::Get::ReceiverScope.new
      caller = BasicObjectSpecs::InstEval::CVar::Get::CallerScope.new

      caller.get_class_variable_with_string(receiver).should == :value_defined_in_caller_scope
    end

    it "gets class variables in the block definition scope when called with a block" do
      receiver = BasicObjectSpecs::InstEval::CVar::Get::ReceiverScope.new
      caller = BasicObjectSpecs::InstEval::CVar::Get::CallerScope.new
      block = BasicObjectSpecs::InstEval::CVar::Get::BlockDefinitionScope.new.block

      caller.get_class_variable_with_block(receiver, block).should == :value_defined_in_block_definition_scope
    end

    it "sets class variables in the caller class when called with a String" do
      receiver = BasicObjectSpecs::InstEval::CVar::Set::ReceiverScope.new
      caller = BasicObjectSpecs::InstEval::CVar::Set::CallerScope.new

      caller.set_class_variable_with_string(receiver, 1)
      BasicObjectSpecs::InstEval::CVar::Set::CallerScope.get_class_variable.should == 1
    end

    it "sets class variables in the block definition scope when called with a block" do
      receiver = BasicObjectSpecs::InstEval::CVar::Set::ReceiverScope.new
      caller = BasicObjectSpecs::InstEval::CVar::Set::CallerScope.new
      block = BasicObjectSpecs::InstEval::CVar::Set::BlockDefinitionScope.new.block_to_assign(1)

      caller.set_class_variable_with_block(receiver, block)
      BasicObjectSpecs::InstEval::CVar::Set::BlockDefinitionScope.get_class_variable.should == 1
    end

    it "does not have access to class variables in the receiver class when called with a String" do
      receiver = BasicObjectSpecs::InstEval::CVar::Get::ReceiverScope.new
      caller = BasicObjectSpecs::InstEval::CVar::Get::CallerWithoutCVarScope.new
      -> { caller.get_class_variable_with_string(receiver) }.should raise_error(NameError, /uninitialized class variable @@cvar/)
    end

    it "does not have access to class variables in the receiver's singleton class when called with a String" do
      receiver = BasicObjectSpecs::InstEval::CVar::Get::ReceiverWithCVarDefinedInSingletonClass
      caller = BasicObjectSpecs::InstEval::CVar::Get::CallerWithoutCVarScope.new
      -> { caller.get_class_variable_with_string(receiver) }.should raise_error(NameError, /uninitialized class variable @@cvar/)
    end
  end

  it "raises a TypeError when defining methods on numerics" do
    -> do
      (1.0).instance_eval { def foo; end }
    end.should raise_error(TypeError)
    -> do
      (1 << 64).instance_eval { def foo; end }
    end.should raise_error(TypeError)
  end

  it "evaluates procs originating from methods" do
    def meth(arg); arg; end

    m = method(:meth)
    obj = Object.new

    obj.instance_eval(&m).should == obj
  end

  it "evaluates string with given filename and linenumber" do
    err = begin
      Object.new.instance_eval("raise", "a_file", 10)
    rescue => e
      e
    end
    err.backtrace.first.split(":")[0..1].should == ["a_file", "10"]
  end

  it "evaluates string with given filename and negative linenumber" do
    err = begin
      Object.new.instance_eval("\n\nraise\n", "b_file", -100)
    rescue => e
      e
    end
    err.backtrace.first.split(":")[0..1].should == ["b_file", "-98"]
  end

  it "has access to the caller's local variables" do
    x = nil

    instance_eval "x = :value"

    x.should == :value
  end

  it "converts string argument with #to_str method" do
    source_code = Object.new
    def source_code.to_str() "1" end

    a = BasicObject.new
    a.instance_eval(source_code).should == 1
  end

  it "raises ArgumentError if returned value is not String" do
    source_code = Object.new
    def source_code.to_str() :symbol end

    a = BasicObject.new
    -> { a.instance_eval(source_code) }.should raise_error(TypeError, /can't convert Object to String/)
  end

  it "converts filename argument with #to_str method" do
    filename = Object.new
    def filename.to_str() "file.rb" end

    err = begin
            Object.new.instance_eval("raise", filename)
          rescue => e
            e
          end
    err.backtrace.first.split(":")[0].should == "file.rb"
  end

  it "raises ArgumentError if returned value is not String" do
    filename = Object.new
    def filename.to_str() :symbol end

    -> { Object.new.instance_eval("raise", filename) }.should raise_error(TypeError, /can't convert Object to String/)
  end

  it "converts lineno argument with #to_int method" do
    lineno = Object.new
    def lineno.to_int() 15 end

    err = begin
            Object.new.instance_eval("raise", "file.rb", lineno)
          rescue => e
            e
          end
    err.backtrace.first.split(":")[1].should == "15"
  end

  it "raises ArgumentError if returned value is not Integer" do
    lineno = Object.new
    def lineno.to_int() :symbol end

    -> { Object.new.instance_eval("raise", "file.rb", lineno) }.should raise_error(TypeError, /can't convert Object to Integer/)
  end
end
