require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/lambda'

# The functionality of lambdas is specified in core/proc

describe "Kernel#lambda" do
  it_behaves_like :kernel_lambda, :lambda

  it "is a private method" do
    Kernel.private_instance_methods(false).should.include?(:lambda)
  end

  it "creates a lambda-style Proc if given a literal block" do
    l = lambda { 42 }
    l.lambda?.should == true
  end

  it "creates a lambda-style Proc if given a literal block via #send" do
    l = send(:lambda) { 42 }
    l.lambda?.should == true
  end

  it "creates a lambda-style Proc if given a literal block via #__send__" do
    l = __send__(:lambda) { 42 }
    l.lambda?.should == true
  end

  it "checks the arity of the call when no args are specified" do
    l = lambda { :called }
    l.call.should == :called

    lambda { l.call(1) }.should.raise(ArgumentError)
    lambda { l.call(1, 2) }.should.raise(ArgumentError)
  end

  it "checks the arity when 1 arg is specified" do
    l = lambda { |a| :called }
    l.call(1).should == :called

    lambda { l.call }.should.raise(ArgumentError)
    lambda { l.call(1, 2) }.should.raise(ArgumentError)
  end

  it "does not check the arity when passing a Proc with &" do
    l = lambda { || :called }
    p = proc { || :called }

    lambda { l.call(1) }.should.raise(ArgumentError)
    p.call(1).should == :called
  end

  it "accepts 0 arguments when used with ||" do
    lambda {
      lambda { || }.call(1)
    }.should.raise(ArgumentError)
  end

  it "strictly checks the arity when 0 or 2..inf args are specified" do
    l = lambda { |a,b| }

    lambda {
      l.call
    }.should.raise(ArgumentError)

    lambda {
      l.call(1)
    }.should.raise(ArgumentError)

    lambda {
      l.call(1,2)
    }.should_not.raise(ArgumentError)
  end

  it "returns from the lambda itself, not the creation site of the lambda" do
    @reached_end_of_method = nil
    def test
      send(:lambda) { return }.call
      @reached_end_of_method = true
    end
    test
    @reached_end_of_method.should == true
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
    klass.new.lambda { 42 }.should.instance_of? Proc
    klass.new.ret.should == 1
  end

  context "when called without a literal block" do
    it "raises when proc isn't a lambda" do
      -> { lambda(&proc{}) }.should.raise(ArgumentError, /the lambda method requires a literal block/)
    end

    it "doesn't warn when proc is lambda" do
      -> { lambda(&lambda{}) }.should_not complain(verbose: true)
    end
  end
end

describe "Kernel.lambda" do
  it "is a public method" do
    Kernel.public_methods(false).should.include?(:lambda)
  end
end
