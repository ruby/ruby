require_relative 'spec_helper'
require_relative 'fixtures/proc'

load_extension("proc")

describe "C-API Proc function" do
  before :each do
    @p = CApiProcSpecs.new
    @prc = @p.rb_proc_new
    @prc2 = @p.rb_proc_new_argv_n
    @prc3 = @p.rb_proc_new_argc
  end

  describe "rb_proc_new" do
    it "returns a new valid Proc" do
      @prc.kind_of?(Proc).should == true
    end

    it "calls the C function wrapped by the Proc instance when sent #call" do
      @p.rb_proc_new_arg.call().should == nil
      @prc.call(:foo_bar).should == ":foo_bar"
      @prc.call([:foo, :bar]).should == "[:foo, :bar]"
    end

    it "calls the C function wrapped by the Proc instance when sent #[]" do
      @prc[:foo_bar].should == ":foo_bar"
      @prc[[:foo, :bar]].should == "[:foo, :bar]"
    end

    it "calls the C function with the arg count in argc" do
      @prc3.call().should == 0
      @prc3.call(:foo).should == 1
      @prc3.call(:foo, :bar).should == 2
    end

    it "calls the C function with arguments in argv" do
      @prc2.call(1, :foo).should == :foo
      @prc2.call(2, :foo, :bar).should == :bar
      -> { @prc2.call(3, :foo, :bar) }.should raise_error(ArgumentError)
    end

    it "calls the C function with the block passed in blockarg" do
      a_block = :foo.to_proc
      @p.rb_proc_new_blockarg.call(&a_block).should == a_block
      @p.rb_proc_new_blockarg.call().should == nil
    end

    it "calls the C function and yields to the block passed in blockarg" do
      @p.rb_proc_new_block_given_p.call() do
      end.should == false
      @p.rb_proc_new_block_given_p.call().should == false
    end

    it "returns a Proc instance correctly described in #inspect without source location" do
      @prc.inspect.should =~ /^#<Proc:([^ :@]*?)>$/
    end

    it "returns a Proc instance with #arity == -1" do
      @prc.arity.should == -1
    end

    it "shouldn't be equal to another one" do
      @prc.should_not == @p.rb_proc_new
    end

    it "returns a Proc instance with #source_location == nil" do
      @prc.source_location.should == nil
    end
  end

  describe "rb_proc_arity" do
    it "returns the correct arity" do
      prc = Proc.new {|a,b,c|}
      @p.rb_proc_arity(prc).should == 3
    end
  end

  describe "rb_proc_call" do
    it "calls the Proc" do
      prc = Proc.new {|a,b| a * b }
      @p.rb_proc_call(prc, [6, 7]).should == 42
    end
  end

  describe "rb_obj_is_proc" do
    it "returns true for Proc" do
      prc = Proc.new {|a,b| a * b }
      @p.rb_obj_is_proc(prc).should be_true
    end

    it "returns true for subclass of Proc" do
      prc = Class.new(Proc).new {}
      @p.rb_obj_is_proc(prc).should be_true
    end

    it "returns false for non Proc instances" do
      @p.rb_obj_is_proc("aoeui").should be_false
      @p.rb_obj_is_proc(123).should be_false
      @p.rb_obj_is_proc(true).should be_false
      @p.rb_obj_is_proc([]).should be_false
    end
  end
end

describe "C-API when calling Proc.new from a C function" do
  before :each do
    @p = CApiProcSpecs.new
  end

  # In the scenarios below: X -> Y means execution context X called to Y.
  # For example: Ruby -> C means a Ruby code called a C function.
  #
  # X -> Y <- X -> Z means execution context X called Y which returned to X,
  # then X called Z.
  # For example: C -> Ruby <- C -> Ruby means a C function called into Ruby
  # code which returned to C, then C called into Ruby code again.

  # Ruby -> C -> Ruby -> Proc.new
  it "raises an ArgumentError when the C function calls a Ruby method that calls Proc.new" do
    -> {
      @p.rb_Proc_new(2) { :called }
    }.should raise_error(ArgumentError)
  end

  # Ruby -> C -> Ruby -> C -> rb_funcall(Proc.new)
  it "raises an ArgumentError when the C function calls a Ruby method and that method calls a C function that calls Proc.new" do
    def @p.redispatch() rb_Proc_new(0) end
    -> { @p.rb_Proc_new(3) { :called } }.should raise_error(ArgumentError)
  end

  # Ruby -> C -> Ruby -> block_given?
  it "returns false from block_given? in a Ruby method called by the C function" do
    @p.rb_Proc_new(6).should be_false
  end
end
