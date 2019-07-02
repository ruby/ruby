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
    l = Kernel.public_send(:lambda) { 42 }
    l.lambda?.should be_true
  end

  ruby_version_is ""..."2.7" do
    it "returned the passed Proc if given an existing Proc" do
      some_proc = proc {}
      l = lambda(&some_proc)
      l.should equal(some_proc)
      l.lambda?.should be_false
    end
  end

  ruby_version_is "2.7" do
    it "returns the passed lambda Proc" do
      some_lambda = lambda {}
      l = lambda(&some_lambda)
      l.should equal(some_lambda)
      l.lambda?.should be_true
    end

    it "converts a proc into a lambda" do
      some_proc = Proc.new { |foo| foo }
      some_proc.lambda?.should be_false
      l = lambda(&some_proc)
      l.lambda?.should be_true
      lambda { l.call }.should raise_error(ArgumentError)
    end

    it "does not mutate the argument when convering it into a lambda" do
      klass = Class.new do
        def self.make_proc
          Proc.new { return 42 }
        end
      end

      some_proc = klass.make_proc
      l = lambda(&some_proc)
      some_proc.lambda?.should be_false
      l.lambda?.should be_true
      l.call.should == 42
      lambda { some_proc.call }.should raise_error(LocalJumpError)
      lambda { some_proc.call("extra args") }.should raise_error(LocalJumpError)
    end
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
end
