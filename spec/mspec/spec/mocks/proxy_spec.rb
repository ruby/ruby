require 'spec_helper'
require 'mspec/mocks/proxy'

RSpec.describe MockObject, ".new" do
  it "creates a new mock object" do
    m = MockObject.new('not a null object')
    expect { m.not_a_method }.to raise_error(NoMethodError)
  end

  it "creates a new mock object that follows the NullObject pattern" do
    m = MockObject.new('null object', :null_object => true)
    expect(m.not_really_a_method).to equal(m)
  end
end

RSpec.describe MockProxy, ".new" do
  it "creates a mock proxy by default" do
    expect(MockProxy.new.mock?).to be_truthy
  end

  it "creates a stub proxy by request" do
    expect(MockProxy.new(:stub).stub?).to be_truthy
  end

  it "sets the call expectation to 1 call for a mock" do
    expect(MockProxy.new.count).to eq([:exactly, 1])
  end

  it "sets the call expectation to any number of times for a stub" do
    expect(MockProxy.new(:stub).count).to eq([:any_number_of_times, 0])
  end
end

RSpec.describe MockProxy, "#count" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns the expected number of calls the mock should receive" do
    expect(@proxy.count).to eq([:exactly, 1])
    expect(@proxy.at_least(3).count).to eq([:at_least, 3])
  end
end

RSpec.describe MockProxy, "#arguments" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns the expected arguments" do
    expect(@proxy.arguments).to eq(:any_args)
  end
end

RSpec.describe MockProxy, "#with" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns self" do
    expect(@proxy.with(:a)).to be_equal(@proxy)
  end

  it "raises an ArgumentError if no arguments are given" do
    expect { @proxy.with }.to raise_error(ArgumentError)
  end

  it "accepts any number of arguments" do
    expect(@proxy.with(1, 2, 3)).to be_an_instance_of(MockProxy)
    expect(@proxy.arguments).to eq([1,2,3])
  end
end

RSpec.describe MockProxy, "#once" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns self" do
    expect(@proxy.once).to be_equal(@proxy)
  end

  it "sets the expected calls to 1" do
    @proxy.once
    expect(@proxy.count).to eq([:exactly, 1])
  end

  it "accepts no arguments" do
    expect { @proxy.once(:a) }.to raise_error
  end
end

RSpec.describe MockProxy, "#twice" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns self" do
    expect(@proxy.twice).to be_equal(@proxy)
  end

  it "sets the expected calls to 2" do
    @proxy.twice
    expect(@proxy.count).to eq([:exactly, 2])
  end

  it "accepts no arguments" do
    expect { @proxy.twice(:b) }.to raise_error
  end
end

RSpec.describe MockProxy, "#exactly" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns self" do
    expect(@proxy.exactly(2)).to be_equal(@proxy)
  end

  it "sets the expected calls to exactly n" do
    @proxy.exactly(5)
    expect(@proxy.count).to eq([:exactly, 5])
  end

  it "does not accept an argument that Integer() cannot convert" do
    expect { @proxy.exactly('x') }.to raise_error
  end
end

RSpec.describe MockProxy, "#at_least" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns self" do
    expect(@proxy.at_least(3)).to be_equal(@proxy)
  end

  it "sets the expected calls to at least n" do
    @proxy.at_least(3)
    expect(@proxy.count).to eq([:at_least, 3])
  end

  it "accepts :once :twice" do
    @proxy.at_least(:once)
    expect(@proxy.count).to eq([:at_least, 1])
    @proxy.at_least(:twice)
    expect(@proxy.count).to eq([:at_least, 2])
  end

  it "does not accept an argument that Integer() cannot convert" do
    expect { @proxy.at_least('x') }.to raise_error
  end
end

RSpec.describe MockProxy, "#at_most" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns self" do
    expect(@proxy.at_most(2)).to be_equal(@proxy)
  end

  it "sets the expected calls to at most n" do
    @proxy.at_most(2)
    expect(@proxy.count).to eq([:at_most, 2])
  end

  it "accepts :once, :twice" do
    @proxy.at_most(:once)
    expect(@proxy.count).to eq([:at_most, 1])
    @proxy.at_most(:twice)
    expect(@proxy.count).to eq([:at_most, 2])
  end

  it "does not accept an argument that Integer() cannot convert" do
    expect { @proxy.at_most('x') }.to raise_error
  end
end

RSpec.describe MockProxy, "#any_number_of_times" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns self" do
    expect(@proxy.any_number_of_times).to be_equal(@proxy)
  end

  it "sets the expected calls to any number of times" do
    @proxy.any_number_of_times
    expect(@proxy.count).to eq([:any_number_of_times, 0])
  end

  it "does not accept an argument" do
    expect { @proxy.any_number_of_times(2) }.to raise_error
  end
end

RSpec.describe MockProxy, "#and_return" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns self" do
    expect(@proxy.and_return(false)).to equal(@proxy)
  end

  it "sets the expected return value" do
    @proxy.and_return(false)
    expect(@proxy.returning).to eq(false)
  end

  it "accepts any number of return values" do
    @proxy.and_return(1, 2, 3)
    expect(@proxy.returning).to eq(1)
    expect(@proxy.returning).to eq(2)
    expect(@proxy.returning).to eq(3)
  end

  it "implicitly sets the expected number of calls" do
    @proxy.and_return(1, 2, 3)
    expect(@proxy.count).to eq([:exactly, 3])
  end

  it "only sets the expected number of calls if it is higher than what is already set" do
    @proxy.at_least(5).times.and_return(1, 2, 3)
    expect(@proxy.count).to eq([:at_least, 5])

    @proxy.at_least(2).times.and_return(1, 2, 3)
    expect(@proxy.count).to eq([:at_least, 3])
  end
end

RSpec.describe MockProxy, "#returning" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns nil by default" do
    expect(@proxy.returning).to be_nil
  end

  it "returns the value set by #and_return" do
    @proxy.and_return(2)
    expect(@proxy.returning).to eq(2)
    expect(@proxy.returning).to eq(2)
  end

  it "returns a sequence of values set by #and_return" do
    @proxy.and_return(1,2,3,4)
    expect(@proxy.returning).to eq(1)
    expect(@proxy.returning).to eq(2)
    expect(@proxy.returning).to eq(3)
    expect(@proxy.returning).to eq(4)
    expect(@proxy.returning).to eq(4)
    expect(@proxy.returning).to eq(4)
  end
end

RSpec.describe MockProxy, "#calls" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns the number of times the proxy is called" do
    expect(@proxy.calls).to eq(0)
  end
end

RSpec.describe MockProxy, "#called" do
  before :each do
    @proxy = MockProxy.new
  end

  it "increments the number of times the proxy is called" do
    @proxy.called
    @proxy.called
    expect(@proxy.calls).to eq(2)
  end
end

RSpec.describe MockProxy, "#times" do
  before :each do
    @proxy = MockProxy.new
  end

  it "is a no-op" do
    expect(@proxy.times).to eq(@proxy)
  end
end

RSpec.describe MockProxy, "#stub?" do
  it "returns true if the proxy is created as a stub" do
    expect(MockProxy.new(:stub).stub?).to be_truthy
  end

  it "returns false if the proxy is created as a mock" do
    expect(MockProxy.new(:mock).stub?).to be_falsey
  end
end

RSpec.describe MockProxy, "#mock?" do
  it "returns true if the proxy is created as a mock" do
    expect(MockProxy.new(:mock).mock?).to be_truthy
  end

  it "returns false if the proxy is created as a stub" do
    expect(MockProxy.new(:stub).mock?).to be_falsey
  end
end

RSpec.describe MockProxy, "#and_yield" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns self" do
    expect(@proxy.and_yield(false)).to equal(@proxy)
  end

  it "sets the expected values to yield" do
    expect(@proxy.and_yield(1).yielding).to eq([[1]])
  end

  it "accepts multiple values to yield" do
    expect(@proxy.and_yield(1, 2, 3).yielding).to eq([[1, 2, 3]])
  end
end

RSpec.describe MockProxy, "#raising" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns nil by default" do
    expect(@proxy.raising).to be_nil
  end

  it "returns the exception object passed to #and_raise" do
    exc = double("exception")
    @proxy.and_raise(exc)
    expect(@proxy.raising).to equal(exc)
  end

  it "returns an instance of RuntimeError when a String is passed to #and_raise" do
    @proxy.and_raise("an error")
    exc = @proxy.raising
    expect(exc).to be_an_instance_of(RuntimeError)
    expect(exc.message).to eq("an error")
  end
end

RSpec.describe MockProxy, "#yielding" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns an empty array by default" do
    expect(@proxy.yielding).to eq([])
  end

  it "returns an array of arrays of values the proxy should yield" do
    @proxy.and_yield(3)
    expect(@proxy.yielding).to eq([[3]])
  end

  it "returns an accumulation of arrays of values the proxy should yield" do
    @proxy.and_yield(1).and_yield(2, 3)
    expect(@proxy.yielding).to eq([[1], [2, 3]])
  end
end

RSpec.describe MockProxy, "#yielding?" do
  before :each do
    @proxy = MockProxy.new
  end

  it "returns false if the proxy is not yielding" do
    expect(@proxy.yielding?).to be_falsey
  end

  it "returns true if the proxy is yielding" do
    @proxy.and_yield(1)
    expect(@proxy.yielding?).to be_truthy
  end
end

RSpec.describe MockIntObject, "#to_int" do
  before :each do
    @int = MockIntObject.new(10)
  end

  it "returns the number if to_int is called" do
    expect(@int.to_int).to eq(10)
    expect(@int.count).to eq([:at_least, 1])
  end

  it "tries to convert the target to int if to_int is called" do
    expect(MockIntObject.new(@int).to_int).to eq(10)
    expect(@int.count).to eq([:at_least, 1])
  end
end
