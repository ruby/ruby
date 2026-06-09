require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/lambda'

# The functionality of Proc objects is specified in core/proc

describe "Kernel.proc" do
  it "is a private method" do
    Kernel.private_instance_methods(false).should.include?(:proc)
  end

  it "creates a proc-style Proc if given a literal block" do
    l = proc { 42 }
    l.lambda?.should == false
  end

  it "returned the passed Proc if given an existing Proc" do
    some_lambda = -> {}
    some_lambda.lambda?.should == true
    l = proc(&some_lambda)
    l.should.equal?(some_lambda)
    l.lambda?.should == true
  end

  it_behaves_like :kernel_lambda, :proc

  it "returns from the creation site of the proc, not just the proc itself" do
    @reached_end_of_method = nil
    def test
      proc { return }.call
      @reached_end_of_method = true
    end
    test
    @reached_end_of_method.should == nil
  end
end

describe "Kernel#proc" do
  def some_method
    proc
  end

  it "raises an ArgumentError when passed no block" do
    -> {
      some_method { "hello" }
    }.should.raise(ArgumentError, 'tried to create Proc object without a block')
  end
end
