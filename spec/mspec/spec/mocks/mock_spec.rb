# This is a bit awkward. Currently the way to verify that the
# opposites are true (for example a failure when the specified
# arguments are NOT provided) is to simply alter the particular
# spec to a failure condition.
require 'spec_helper'
require 'mspec/runner/mspec'
require 'mspec/mocks/mock'
require 'mspec/mocks/proxy'

RSpec.describe Mock, ".mocks" do
  it "returns a Hash" do
    expect(Mock.mocks).to be_kind_of(Hash)
  end
end

RSpec.describe Mock, ".stubs" do
  it "returns a Hash" do
    expect(Mock.stubs).to be_kind_of(Hash)
  end
end

RSpec.describe Mock, ".replaced_name" do
  it "returns the name for a method that is being replaced by a mock method" do
    m = double('a fake id')
    expect(Mock.replaced_name(m, :method_call)).to eq(:"__mspec_#{m.object_id}_method_call__")
  end
end

RSpec.describe Mock, ".replaced_key" do
  it "returns a key used internally by Mock" do
    m = double('a fake id')
    expect(Mock.replaced_key(m, :method_call)).to eq([:"__mspec_#{m.object_id}_method_call__", :method_call])
  end
end

RSpec.describe Mock, ".replaced?" do
  before :each do
    @mock = double('install_method')
    allow(MSpec).to receive(:actions)
    allow(MSpec).to receive(:current).and_return(double("spec state").as_null_object)
  end

  it "returns true if a method has been stubbed on an object" do
    Mock.install_method @mock, :method_call
    expect(Mock.replaced?(Mock.replaced_name(@mock, :method_call))).to be_truthy
  end

  it "returns true if a method has been mocked on an object" do
    Mock.install_method @mock, :method_call, :stub
    expect(Mock.replaced?(Mock.replaced_name(@mock, :method_call))).to be_truthy
  end

  it "returns false if a method has not been stubbed or mocked" do
    expect(Mock.replaced?(Mock.replaced_name(@mock, :method_call))).to be_falsey
  end
end

RSpec.describe Mock, ".name_or_inspect" do
  before :each do
    @mock = double("I have a #name")
  end

  it "returns the value of @name if set" do
    @mock.instance_variable_set(:@name, "Myself")
    expect(Mock.name_or_inspect(@mock)).to eq("Myself")
  end
end

RSpec.describe Mock, ".install_method for mocks" do
  before :each do
    @mock = double('install_method')
    allow(MSpec).to receive(:actions)
    allow(MSpec).to receive(:current).and_return(double("spec state").as_null_object)
  end

  after :each do
    Mock.reset
  end

  it "returns a MockProxy instance" do
    expect(Mock.install_method(@mock, :method_call)).to be_an_instance_of(MockProxy)
  end

  it "does not override a previously mocked method with the same name" do
    Mock.install_method(@mock, :method_call).with(:a, :b).and_return(1)
    Mock.install_method(@mock, :method_call).with(:c).and_return(2)
    @mock.method_call(:a, :b)
    @mock.method_call(:c)
    expect { @mock.method_call(:d) }.to raise_error(SpecExpectationNotMetError)
  end

  # This illustrates RSpec's behavior. This spec fails in mock call count verification
  # on RSpec (i.e. Mock 'foo' expected :foo with (any args) once, but received it 0 times)
  # and we mimic the behavior of RSpec.
  #
  # describe "A mock receiving multiple calls to #should_receive" do
  #   it "returns the first value mocked" do
  #     m = mock 'multiple #should_receive'
  #     m.should_receive(:foo).and_return(true)
  #     m.foo.should == true
  #     m.should_receive(:foo).and_return(false)
  #     m.foo.should == true
  #   end
  # end
  #
  it "does not override a previously mocked method having the same arguments" do
    Mock.install_method(@mock, :method_call).with(:a).and_return(true)
    expect(@mock.method_call(:a)).to eq(true)
    Mock.install_method(@mock, :method_call).with(:a).and_return(false)
    expect(@mock.method_call(:a)).to eq(true)
    expect { Mock.verify_count }.to raise_error(SpecExpectationNotMetError)
  end

  it "properly sends #respond_to? calls to the aliased respond_to? method when not matching mock expectations" do
    Mock.install_method(@mock, :respond_to?).with(:to_str).and_return('mock to_str')
    Mock.install_method(@mock, :respond_to?).with(:to_int).and_return('mock to_int')
    expect(@mock.respond_to?(:to_str)).to eq('mock to_str')
    expect(@mock.respond_to?(:to_int)).to eq('mock to_int')
    expect(@mock.respond_to?(:to_s)).to eq(true)
    expect(@mock.respond_to?(:not_really_a_real_method_seriously)).to eq(false)
  end

  it "adds to the expectation tally" do
    state = double("run state").as_null_object
    allow(state).to receive(:state).and_return(double("spec state"))
    expect(MSpec).to receive(:current).and_return(state)
    expect(MSpec).to receive(:actions).with(:expectation, state.state)
    Mock.install_method(@mock, :method_call).and_return(1)
    expect(@mock.method_call).to eq(1)
  end

  it "registers that an expectation has been encountered" do
    state = double("run state").as_null_object
    allow(state).to receive(:state).and_return(double("spec state"))
    expect(MSpec).to receive(:expectation)
    Mock.install_method(@mock, :method_call).and_return(1)
    expect(@mock.method_call).to eq(1)
  end
end

RSpec.describe Mock, ".install_method for stubs" do
  before :each do
    @mock = double('install_method')
    allow(MSpec).to receive(:actions)
    allow(MSpec).to receive(:current).and_return(double("spec state").as_null_object)
  end

  after :each do
    Mock.cleanup
  end

  it "returns a MockProxy instance" do
    expect(Mock.install_method(@mock, :method_call, :stub)).to be_an_instance_of(MockProxy)
  end

  # This illustrates RSpec's behavior. This spec passes on RSpec and we mimic it
  #
  # describe "A mock receiving multiple calls to #stub" do
  #   it "returns the last value stubbed" do
  #     m = mock 'multiple #stub'
  #     m.stub(:foo).and_return(true)
  #     m.foo.should == true
  #     m.stub(:foo).and_return(false)
  #     m.foo.should == false
  #   end
  # end
  it "inserts new stubs before old stubs" do
    Mock.install_method(@mock, :method_call, :stub).with(:a).and_return(true)
    expect(@mock.method_call(:a)).to eq(true)
    Mock.install_method(@mock, :method_call, :stub).with(:a).and_return(false)
    expect(@mock.method_call(:a)).to eq(false)
    Mock.verify_count
  end

  it "does not add to the expectation tally" do
    state = double("run state").as_null_object
    allow(state).to receive(:state).and_return(double("spec state"))
    expect(MSpec).not_to receive(:actions)
    Mock.install_method(@mock, :method_call, :stub).and_return(1)
    expect(@mock.method_call).to eq(1)
  end
end

RSpec.describe Mock, ".install_method" do
  before :each do
    @mock = double('install_method')
    allow(MSpec).to receive(:actions)
    allow(MSpec).to receive(:current).and_return(double("spec state").as_null_object)
  end

  after :each do
    Mock.cleanup
  end

  it "does not alias a mocked or stubbed method when installing a new mock or stub" do
    expect(@mock).not_to respond_to(:method_call)

    Mock.install_method @mock, :method_call
    expect(@mock).to respond_to(:method_call)
    expect(@mock).not_to respond_to(Mock.replaced_name(@mock, :method_call))

    Mock.install_method @mock, :method_call, :stub
    expect(@mock).to respond_to(:method_call)
    expect(@mock).not_to respond_to(Mock.replaced_name(@mock, :method_call))
  end
end

class MockAndRaiseError < Exception; end

RSpec.describe Mock, ".verify_call" do
  before :each do
    allow(MSpec).to receive(:actions)
    allow(MSpec).to receive(:current).and_return(double("spec state").as_null_object)

    @mock = double('verify_call')
    @proxy = Mock.install_method @mock, :method_call
  end

  after :each do
    ScratchPad.clear
    Mock.cleanup
  end

  it "does not raise an exception when the mock method receives the expected arguments" do
    @proxy.with(1, 'two', :three)
    Mock.verify_call @mock, :method_call, 1, 'two', :three
  end

  it "raises an SpecExpectationNotMetError when the mock method does not receive the expected arguments" do
    @proxy.with(4, 2)
    expect {
      Mock.verify_call @mock, :method_call, 42
    }.to raise_error(SpecExpectationNotMetError)
  end

  it "raises an SpecExpectationNotMetError when the mock method is called with arguments but expects none" do
    expect {
      @proxy.with(:no_args)
      Mock.verify_call @mock, :method_call, "hello"
    }.to raise_error(SpecExpectationNotMetError)
  end

  it "raises an SpecExpectationNotMetError when the mock method is called with no arguments but expects some" do
    @proxy.with("hello", "beautiful", "world")
    expect {
      Mock.verify_call @mock, :method_call
    }.to raise_error(SpecExpectationNotMetError)
  end

  it "does not raise an exception when the mock method is called with arguments and is expecting :any_args" do
    @proxy.with(:any_args)
    Mock.verify_call @mock, :method_call, 1, 2, 3
  end

  it "yields a passed block when it is expected to" do
    @proxy.and_yield()
    Mock.verify_call @mock, :method_call do
      ScratchPad.record true
    end
    expect(ScratchPad.recorded).to eq(true)
  end

  it "does not yield a passed block when it is not expected to" do
    Mock.verify_call @mock, :method_call do
      ScratchPad.record true
    end
    expect(ScratchPad.recorded).to eq(nil)
  end

  it "can yield subsequently" do
    @proxy.and_yield(1).and_yield(2).and_yield(3)

    ScratchPad.record []
    Mock.verify_call @mock, :method_call do |arg|
      ScratchPad << arg
    end
    expect(ScratchPad.recorded).to eq([1, 2, 3])
  end

  it "can yield and return an expected value" do
    @proxy.and_yield(1).and_return(3)

    expect(Mock.verify_call(@mock, :method_call) { |arg| ScratchPad.record arg }).to eq(3)
    expect(ScratchPad.recorded).to eq(1)
  end

  it "raises an exception when it is expected to yield but no block is given" do
    @proxy.and_yield(1, 2, 3)
    expect {
      Mock.verify_call(@mock, :method_call)
    }.to raise_error(SpecExpectationNotMetError)
  end

  it "raises an exception when it is expected to yield more arguments than the block can take" do
    @proxy.and_yield(1, 2, 3)
    expect {
      Mock.verify_call(@mock, :method_call) {|a, b|}
    }.to raise_error(SpecExpectationNotMetError)
  end

  it "does not raise an exception when it is expected to yield to a block that can take any number of arguments" do
    @proxy.and_yield(1, 2, 3)
    expect {
      Mock.verify_call(@mock, :method_call) {|*a|}
    }.not_to raise_error
  end

  it "raises an exception when expected to" do
    @proxy.and_raise(MockAndRaiseError)
    expect {
      Mock.verify_call @mock, :method_call
    }.to raise_error(MockAndRaiseError)
  end
end

RSpec.describe Mock, ".verify_call mixing mocks and stubs" do
  before :each do
    allow(MSpec).to receive(:actions)
    allow(MSpec).to receive(:current).and_return(double("spec state").as_null_object)

    @mock = double('verify_call')
  end

  after :each do
    ScratchPad.clear
    Mock.cleanup
  end

  it "checks the mock arguments when a mock is defined after a stub" do
    Mock.install_method @mock, :method_call, :stub
    Mock.install_method(@mock, :method_call, :mock).with("arg")

    expect {
      @mock.method_call
    }.to raise_error(SpecExpectationNotMetError, /called with unexpected arguments \(\)/)

    expect {
      @mock.method_call("a", "b")
    }.to raise_error(SpecExpectationNotMetError, /called with unexpected arguments \("a", "b"\)/)

    expect {
      @mock.method_call("foo")
    }.to raise_error(SpecExpectationNotMetError, /called with unexpected arguments \("foo"\)/)

    @mock.method_call("arg")
  end

  it "checks the mock arguments when a stub is defined after a mock" do
    Mock.install_method(@mock, :method_call, :mock).with("arg")
    Mock.install_method @mock, :method_call, :stub

    expect {
      @mock.method_call
    }.to raise_error(SpecExpectationNotMetError, /called with unexpected arguments \(\)/)

    expect {
      @mock.method_call("a", "b")
    }.to raise_error(SpecExpectationNotMetError, /called with unexpected arguments \("a", "b"\)/)

    expect {
      @mock.method_call("foo")
    }.to raise_error(SpecExpectationNotMetError, /called with unexpected arguments \("foo"\)/)

    @mock.method_call("arg")
  end
end

RSpec.describe Mock, ".verify_count" do
  before :each do
    allow(MSpec).to receive(:actions)
    allow(MSpec).to receive(:current).and_return(double("spec state").as_null_object)

    @mock = double('verify_count')
    @proxy = Mock.install_method @mock, :method_call
  end

  after :each do
    Mock.cleanup
  end

  it "does not raise an exception when the mock receives at least the expected number of calls" do
    @proxy.at_least(2)
    @mock.method_call
    @mock.method_call
    Mock.verify_count
  end

  it "raises an SpecExpectationNotMetError when the mock receives less than at least the expected number of calls" do
    @proxy.at_least(2)
    @mock.method_call
    expect { Mock.verify_count }.to raise_error(SpecExpectationNotMetError)
  end

  it "does not raise an exception when the mock receives at most the expected number of calls" do
    @proxy.at_most(2)
    @mock.method_call
    @mock.method_call
    Mock.verify_count
  end

  it "raises an SpecExpectationNotMetError when the mock receives more than at most the expected number of calls" do
    @proxy.at_most(2)
    @mock.method_call
    @mock.method_call
    @mock.method_call
    expect { Mock.verify_count }.to raise_error(SpecExpectationNotMetError)
  end

  it "does not raise an exception when the mock receives exactly the expected number of calls" do
    @proxy.exactly(2)
    @mock.method_call
    @mock.method_call
    Mock.verify_count
  end

  it "raises an SpecExpectationNotMetError when the mock receives less than exactly the expected number of calls" do
    @proxy.exactly(2)
    @mock.method_call
    expect { Mock.verify_count }.to raise_error(SpecExpectationNotMetError)
  end

  it "raises an SpecExpectationNotMetError when the mock receives more than exactly the expected number of calls" do
    @proxy.exactly(2)
    @mock.method_call
    @mock.method_call
    @mock.method_call
    expect { Mock.verify_count }.to raise_error(SpecExpectationNotMetError)
  end
end

RSpec.describe Mock, ".verify_count mixing mocks and stubs" do
  before :each do
    allow(MSpec).to receive(:actions)
    allow(MSpec).to receive(:current).and_return(double("spec state").as_null_object)

    @mock = double('verify_count')
  end

  after :each do
    Mock.cleanup
  end

  it "does not raise an exception for a stubbed method that is never called" do
    Mock.install_method @mock, :method_call, :stub
    Mock.verify_count
  end

  it "verifies the calls to the mocked method when a mock is defined after a stub" do
    Mock.install_method @mock, :method_call, :stub
    Mock.install_method @mock, :method_call, :mock

    expect {
      Mock.verify_count
    }.to raise_error(SpecExpectationNotMetError, /received it 0 times/)

    @mock.method_call
    Mock.verify_count
  end

  it "verifies the calls to the mocked method when a mock is defined before a stub" do
    Mock.install_method @mock, :method_call, :mock
    Mock.install_method @mock, :method_call, :stub

    expect {
      Mock.verify_count
    }.to raise_error(SpecExpectationNotMetError, /received it 0 times/)

    @mock.method_call
    Mock.verify_count
  end
end

RSpec.describe Mock, ".cleanup" do
  before :each do
    allow(MSpec).to receive(:actions)
    allow(MSpec).to receive(:current).and_return(double("spec state").as_null_object)

    @mock = double('cleanup')
    @proxy = Mock.install_method @mock, :method_call
  end

  after :each do
    Mock.cleanup
  end

  it "removes the mock method call if it did not override an existing method" do
    expect(@mock).to respond_to(:method_call)

    Mock.cleanup
    expect(@mock).not_to respond_to(:method_call)
  end

  it "removes the replaced method if the mock method overrides an existing method" do
    def @mock.already_here() :hey end
    expect(@mock).to respond_to(:already_here)
    replaced_name = Mock.replaced_name(@mock, :already_here)
    Mock.install_method @mock, :already_here
    expect(@mock).to respond_to(replaced_name)

    Mock.cleanup
    expect(@mock).not_to respond_to(replaced_name)
    expect(@mock).to respond_to(:already_here)
    expect(@mock.already_here).to eq(:hey)
  end

  it "removes all mock expectations" do
    expect(Mock.mocks).to eq({ Mock.replaced_key(@mock, :method_call) => [@proxy] })
    Mock.cleanup
    expect(Mock.mocks).to eq({})
  end

  it "removes all stubs" do
    Mock.cleanup # remove @proxy
    @stub = Mock.install_method @mock, :method_call, :stub
    expect(Mock.stubs).to eq({ Mock.replaced_key(@mock, :method_call) => [@stub] })
    Mock.cleanup
    expect(Mock.stubs).to eq({})
  end

  it "removes the replaced name for mocks" do
    replaced_key = Mock.replaced_key(@mock, :method_call)
    expect(Mock).to receive(:clear_replaced).with(replaced_key)

    replaced_name = Mock.replaced_name(@mock, :method_call)
    expect(Mock.replaced?(replaced_name)).to be_truthy

    Mock.cleanup
    expect(Mock.replaced?(replaced_name)).to be_falsey
  end
end
