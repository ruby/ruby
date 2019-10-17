require 'spec_helper'
require 'mspec/mocks/proxy'

describe MockObject, ".new" do
  it "creates a new mock object" do
    m = MockObject.new('not a null object')
    lambda { m.not_a_method }.should raise_error(NoMethodError)
  end

  it "creates a new mock object that follows the NullObject pattern" do
    m = MockObject.new('null object', :null_object => true)
    m.not_really_a_method.should equal(m)
  end
end

describe MockProxy, ".new" do
  it "creates a mock proxy by default" do
    MockProxy.new.mock?.should be_true
  end

  it "creates a stub proxy by request" do
    MockProxy.new(:stub).stub?.should be_true
  end

  it "sets the call expectation to 1 call for a mock" do
    MockProxy.new.count.should == [:exactly, 1]
  end

  it "sets the call expectation to any number of times for a stub" do
    MockProxy.new(:stub).count.should == [:any_number_of_times, 0]
  end
end

describe MockProxy, "#count" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns the expected number of calls the mock should receive" do
    @proxy.count.should == [:exactly, 1]
    @proxy.at_least(3).count.should == [:at_least, 3]
  end
end

describe MockProxy, "#arguments" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns the expected arguments" do
    @proxy.arguments.should == :any_args
  end
end

describe MockProxy, "#with" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns self" do
    @proxy.with(:a).should be_equal(@proxy)
  end

  it "raises an ArgumentError if no arguments are given" do
    lambda { @proxy.with }.should raise_error(ArgumentError)
  end

  it "accepts any number of arguments" do
    @proxy.with(1, 2, 3).should be_an_instance_of(MockProxy)
    @proxy.arguments.should == [1,2,3]
  end
end

describe MockProxy, "#once" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns self" do
    @proxy.once.should be_equal(@proxy)
  end

  it "sets the expected calls to 1" do
    @proxy.once
    @proxy.count.should == [:exactly, 1]
  end

  it "accepts no arguments" do
    lambda { @proxy.once(:a) }.should raise_error
  end
end

describe MockProxy, "#twice" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns self" do
    @proxy.twice.should be_equal(@proxy)
  end

  it "sets the expected calls to 2" do
    @proxy.twice
    @proxy.count.should == [:exactly, 2]
  end

  it "accepts no arguments" do
    lambda { @proxy.twice(:b) }.should raise_error
  end
end

describe MockProxy, "#exactly" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns self" do
    @proxy.exactly(2).should be_equal(@proxy)
  end

  it "sets the expected calls to exactly n" do
    @proxy.exactly(5)
    @proxy.count.should == [:exactly, 5]
  end

  it "does not accept an argument that Integer() cannot convert" do
    lambda { @proxy.exactly('x') }.should raise_error
  end
end

describe MockProxy, "#at_least" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns self" do
    @proxy.at_least(3).should be_equal(@proxy)
  end

  it "sets the expected calls to at least n" do
    @proxy.at_least(3)
    @proxy.count.should == [:at_least, 3]
  end

  it "accepts :once :twice" do
    @proxy.at_least(:once)
    @proxy.count.should == [:at_least, 1]
    @proxy.at_least(:twice)
    @proxy.count.should == [:at_least, 2]
  end

  it "does not accept an argument that Integer() cannot convert" do
    lambda { @proxy.at_least('x') }.should raise_error
  end
end

describe MockProxy, "#at_most" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns self" do
    @proxy.at_most(2).should be_equal(@proxy)
  end

  it "sets the expected calls to at most n" do
    @proxy.at_most(2)
    @proxy.count.should == [:at_most, 2]
  end

  it "accepts :once, :twice" do
    @proxy.at_most(:once)
    @proxy.count.should == [:at_most, 1]
    @proxy.at_most(:twice)
    @proxy.count.should == [:at_most, 2]
  end

  it "does not accept an argument that Integer() cannot convert" do
    lambda { @proxy.at_most('x') }.should raise_error
  end
end

describe MockProxy, "#any_number_of_times" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns self" do
    @proxy.any_number_of_times.should be_equal(@proxy)
  end

  it "sets the expected calls to any number of times" do
    @proxy.any_number_of_times
    @proxy.count.should == [:any_number_of_times, 0]
  end

  it "does not accept an argument" do
    lambda { @proxy.any_number_of_times(2) }.should raise_error
  end
end

describe MockProxy, "#and_return" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns self" do
    @proxy.and_return(false).should equal(@proxy)
  end

  it "sets the expected return value" do
    @proxy.and_return(false)
    @proxy.returning.should == false
  end

  it "accepts any number of return values" do
    @proxy.and_return(1, 2, 3)
    @proxy.returning.should == 1
    @proxy.returning.should == 2
    @proxy.returning.should == 3
  end

  it "implicitly sets the expected number of calls" do
    @proxy.and_return(1, 2, 3)
    @proxy.count.should == [:exactly, 3]
  end

  it "only sets the expected number of calls if it is higher than what is already set" do
    @proxy.at_least(5).times.and_return(1, 2, 3)
    @proxy.count.should == [:at_least, 5]

    @proxy.at_least(2).times.and_return(1, 2, 3)
    @proxy.count.should == [:at_least, 3]
  end
end

describe MockProxy, "#returning" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns nil by default" do
    @proxy.returning.should be_nil
  end

  it "returns the value set by #and_return" do
    @proxy.and_return(2)
    @proxy.returning.should == 2
    @proxy.returning.should == 2
  end

  it "returns a sequence of values set by #and_return" do
    @proxy.and_return(1,2,3,4)
    @proxy.returning.should == 1
    @proxy.returning.should == 2
    @proxy.returning.should == 3
    @proxy.returning.should == 4
    @proxy.returning.should == 4
    @proxy.returning.should == 4
  end
end

describe MockProxy, "#calls" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns the number of times the proxy is called" do
    @proxy.calls.should == 0
  end
end

describe MockProxy, "#called" do
  before :each do
    @proxy = MockProxy.new
  end

  it "increments the number of times the proxy is called" do
    @proxy.called
    @proxy.called
    @proxy.calls.should == 2
  end
end

describe MockProxy, "#times" do
  before :each do
    @proxy = MockProxy.new
  end

  it "is a no-op" do
    @proxy.times.should == @proxy
  end
end

describe MockProxy, "#stub?" do
  it "returns true if the proxy is created as a stub" do
    MockProxy.new(:stub).stub?.should be_true
  end

  it "returns false if the proxy is created as a mock" do
    MockProxy.new(:mock).stub?.should be_false
  end
end

describe MockProxy, "#mock?" do
  it "returns true if the proxy is created as a mock" do
    MockProxy.new(:mock).mock?.should be_true
  end

  it "returns false if the proxy is created as a stub" do
    MockProxy.new(:stub).mock?.should be_false
  end
end

describe MockProxy, "#and_yield" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns self" do
    @proxy.and_yield(false).should equal(@proxy)
  end

  it "sets the expected values to yield" do
    @proxy.and_yield(1).yielding.should == [[1]]
  end

  it "accepts multiple values to yield" do
    @proxy.and_yield(1, 2, 3).yielding.should == [[1, 2, 3]]
  end
end

describe MockProxy, "#raising" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns nil by default" do
    @proxy.raising.should be_nil
  end

  it "returns the exception object passed to #and_raise" do
    exc = double("exception")
    @proxy.and_raise(exc)
    @proxy.raising.should equal(exc)
  end

  it "returns an instance of RuntimeError when a String is passed to #and_raise" do
    @proxy.and_raise("an error")
    exc = @proxy.raising
    exc.should be_an_instance_of(RuntimeError)
    exc.message.should == "an error"
  end
end

describe MockProxy, "#yielding" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns an empty array by default" do
    @proxy.yielding.should == []
  end

  it "returns an array of arrays of values the proxy should yield" do
    @proxy.and_yield(3)
    @proxy.yielding.should == [[3]]
  end

  it "returns an accumulation of arrays of values the proxy should yield" do
    @proxy.and_yield(1).and_yield(2, 3)
    @proxy.yielding.should == [[1], [2, 3]]
  end
end

describe MockProxy, "#yielding?" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns false if the proxy is not yielding" do
    @proxy.yielding?.should be_false
  end

  it "returns true if the proxy is yielding" do
    @proxy.and_yield(1)
    @proxy.yielding?.should be_true
  end
end

describe MockIntObject, "#to_int" do
  before :each do
    @int = MockIntObject.new(10)
  end

  it "returns the number if to_int is called" do
    @int.to_int.should == 10
    @int.count.should == [:at_least, 1]
  end

  it "tries to convert the target to int if to_int is called" do
    MockIntObject.new(@int).to_int.should == 10
    @int.count.should == [:at_least, 1]
  end
end
