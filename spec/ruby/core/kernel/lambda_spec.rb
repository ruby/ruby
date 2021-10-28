require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/lambda'

# The functionality of lambdas is specified in core/proc

describe "Kernel.lambda" do
  it_behaves_like :kernel_lambda, :lambda

  it "is a private method" do
    Kernel.should have_private_instance_method(:lambda)
  end

  it "creates a lambda-style Proc if given a literal block" do
    l = lambda { 42 }
    l.lambda?.should be_true
  end

  it "creates a lambda-style Proc if given a literal block via #send" do
    l = send(:lambda) { 42 }
    l.lambda?.should be_true
  end

  it "creates a lambda-style Proc if given a literal block via #__send__" do
    l = __send__(:lambda) { 42 }
    l.lambda?.should be_true
  end

  it "creates a lambda-style Proc if given a literal block via Kernel.public_send" do
    suppress_warning do
      l = Kernel.public_send(:lambda) { 42 }
      l.lambda?.should be_true
    end
  end

  it "returns the passed Proc if given an existing Proc" do
    some_proc = proc {}
    l = suppress_warning {lambda(&some_proc)}
    l.should equal(some_proc)
    l.lambda?.should be_false
  end

  it "creates a lambda-style Proc when called with zsuper" do
    suppress_warning do
      l = KernelSpecs::LambdaSpecs::ForwardBlockWithZSuper.new.lambda { 42 }
      l.lambda?.should be_true
      l.call.should == 42

      lambda { l.call(:extra) }.should raise_error(ArgumentError)
    end
  end

  it "returns the passed Proc if given an existing Proc through super" do
    some_proc = proc { }
    l = KernelSpecs::LambdaSpecs::SuperAmpersand.new.lambda(&some_proc)
    l.should equal(some_proc)
    l.lambda?.should be_false
  end

  it "does not create lambda-style Procs when captured with #method" do
    kernel_lambda = method(:lambda)
    l = suppress_warning {kernel_lambda.call { 42 }}
    l.lambda?.should be_false
    l.call(:extra).should == 42
  end

  it "checks the arity of the call when no args are specified" do
    l = lambda { :called }
    l.call.should == :called

    lambda { l.call(1) }.should raise_error(ArgumentError)
    lambda { l.call(1, 2) }.should raise_error(ArgumentError)
  end

  it "checks the arity when 1 arg is specified" do
    l = lambda { |a| :called }
    l.call(1).should == :called

    lambda { l.call }.should raise_error(ArgumentError)
    lambda { l.call(1, 2) }.should raise_error(ArgumentError)
  end

  it "does not check the arity when passing a Proc with &" do
    l = lambda { || :called }
    p = proc { || :called }

    lambda { l.call(1) }.should raise_error(ArgumentError)
    p.call(1).should == :called
  end

  it "accepts 0 arguments when used with ||" do
    lambda {
      lambda { || }.call(1)
    }.should raise_error(ArgumentError)
  end

  it "strictly checks the arity when 0 or 2..inf args are specified" do
    l = lambda { |a,b| }

    lambda {
      l.call
    }.should raise_error(ArgumentError)

    lambda {
      l.call(1)
    }.should raise_error(ArgumentError)

    lambda {
      l.call(1,2)
    }.should_not raise_error(ArgumentError)
  end

  it "returns from the lambda itself, not the creation site of the lambda" do
    @reached_end_of_method = nil
    def test
      send(:lambda) { return }.call
      @reached_end_of_method = true
    end
    test
    @reached_end_of_method.should be_true
  end

  it "allows long returns to flow through it" do
    KernelSpecs::Lambda.new.outer.should == :good
  end

  it "treats the block as a Proc when lambda is re-defined" do
    klass = Class.new do
      def lambda (&block); block; end
      def ret
        lambda { return 1 }.call
        2
      end
    end
    klass.new.lambda { 42 }.should be_an_instance_of Proc
    klass.new.ret.should == 1
  end

  ruby_version_is "3.0" do
    context "when called without a literal block" do
      it "warns when proc isn't a lambda" do
        -> { lambda(&proc{}) }.should complain("#{__FILE__}:#{__LINE__}: warning: lambda without a literal block is deprecated; use the proc without lambda instead\n")
      end

      it "doesn't warn when proc is lambda" do
        -> { lambda(&lambda{}) }.should_not complain(verbose: true)
      end
    end
  end
end
