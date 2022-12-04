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

  it "has access to receiver's instance variables" do
    BasicObjectSpecs::IVars.new.instance_eval { @secret }.should == 99
    BasicObjectSpecs::IVars.new.instance_eval("@secret").should == 99
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

  it "sets class variables in the receiver" do
    BasicObjectSpecs::InstEvalCVar.class_variables.should include(:@@count)
    BasicObjectSpecs::InstEvalCVar.send(:class_variable_get, :@@count).should == 2
  end

  it "makes the receiver metaclass the scoped class when used with a string" do
    obj = Object.new
    obj.instance_eval %{
      class B; end
      B
    }
    obj.singleton_class.const_get(:B).should be_an_instance_of(Class)
  end

  it "gets constants in the receiver if a string given" do
    BasicObjectSpecs::InstEvalOuter::Inner::X_BY_STR.should == 2
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

quarantine! do # Not clean, leaves cvars lying around to break other specs
  it "scopes class var accesses in the caller when called on an Integer" do
    # Integer can take instance vars
    Integer.class_eval "@@__tmp_instance_eval_spec = 1"
    (defined? @@__tmp_instance_eval_spec).should be_nil

    @@__tmp_instance_eval_spec = 2
    1.instance_eval { @@__tmp_instance_eval_spec }.should == 2
    Integer.__send__(:remove_class_variable, :@@__tmp_instance_eval_spec)
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
