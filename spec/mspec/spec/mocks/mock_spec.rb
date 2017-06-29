# This is a bit awkward. Currently the way to verify that the
# opposites are true (for example a failure when the specified
# arguments are NOT provided) is to simply alter the particular
# spec to a failure condition.
require 'spec_helper'
require 'mspec/runner/mspec'
require 'mspec/mocks/mock'
require 'mspec/mocks/proxy'

describe Mock, ".mocks" do
  it "returns a Hash" do
    Mock.mocks.should be_kind_of(Hash)
  end
end

describe Mock, ".stubs" do
  it "returns a Hash" do
    Mock.stubs.should be_kind_of(Hash)
  end
end

describe Mock, ".replaced_name" do
  it "returns the name for a method that is being replaced by a mock method" do
    m = double('a fake id')
    Mock.replaced_name(m, :method_call).should == :"__mspec_#{m.object_id}_method_call__"
  end
end

describe Mock, ".replaced_key" do
  it "returns a key used internally by Mock" do
    m = double('a fake id')
    Mock.replaced_key(m, :method_call).should == [:"__mspec_#{m.object_id}_method_call__", :method_call]
  end
end

describe Mock, ".replaced?" do
  before :each do
    @mock = double('install_method')
    MSpec.stub(:actions)
    MSpec.stub(:current).and_return(double("spec state").as_null_object)
  end

  it "returns true if a method has been stubbed on an object" do
    Mock.install_method @mock, :method_call
    Mock.replaced?(Mock.replaced_name(@mock, :method_call)).should be_true
  end

  it "returns true if a method has been mocked on an object" do
    Mock.install_method @mock, :method_call, :stub
    Mock.replaced?(Mock.replaced_name(@mock, :method_call)).should be_true
  end

  it "returns false if a method has not been stubbed or mocked" do
    Mock.replaced?(Mock.replaced_name(@mock, :method_call)).should be_false
  end
end

describe Mock, ".name_or_inspect" do
  before :each do
    @mock = double("I have a #name")
  end

  it "returns the value of @name if set" do
    @mock.instance_variable_set(:@name, "Myself")
    Mock.name_or_inspect(@mock).should == "Myself"
  end
end

describe Mock, ".install_method for mocks" do
  before :each do
    @mock = double('install_method')
    MSpec.stub(:actions)
    MSpec.stub(:current).and_return(double("spec state").as_null_object)
  end

  after :each do
    Mock.cleanup
  end

  it "returns a MockProxy instance" do
    Mock.install_method(@mock, :method_call).should be_an_instance_of(MockProxy)
  end

  it "does not override a previously mocked method with the same name" do
    Mock.install_method(@mock, :method_call).with(:a, :b).and_return(1)
    Mock.install_method(@mock, :method_call).with(:c).and_return(2)
    @mock.method_call(:a, :b)
    @mock.method_call(:c)
    lambda { @mock.method_call(:d) }.should raise_error(SpecExpectationNotMetError)
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
    @mock.method_call(:a).should == true
    Mock.install_method(@mock, :method_call).with(:a).and_return(false)
    @mock.method_call(:a).should == true
    lambda { Mock.verify_count }.should raise_error(SpecExpectationNotMetError)
  end

  it "properly sends #respond_to? calls to the aliased respond_to? method when not matching mock expectations" do
    Mock.install_method(@mock, :respond_to?).with(:to_str).and_return('mock to_str')
    Mock.install_method(@mock, :respond_to?).with(:to_int).and_return('mock to_int')
    @mock.respond_to?(:to_str).should == 'mock to_str'
    @mock.respond_to?(:to_int).should == 'mock to_int'
    @mock.respond_to?(:to_s).should == true
    @mock.respond_to?(:not_really_a_real_method_seriously).should == false
  end

  it "adds to the expectation tally" do
    state = double("run state").as_null_object
    state.stub(:state).and_return(double("spec state"))
    MSpec.should_receive(:current).and_return(state)
    MSpec.should_receive(:actions).with(:expectation, state.state)
    Mock.install_method(@mock, :method_call).and_return(1)
    @mock.method_call.should == 1
  end

  it "registers that an expectation has been encountered" do
    state = double("run state").as_null_object
    state.stub(:state).and_return(double("spec state"))
    MSpec.should_receive(:expectation)
    Mock.install_method(@mock, :method_call).and_return(1)
    @mock.method_call.should == 1
  end
end

describe Mock, ".install_method for stubs" do
  before :each do
    @mock = double('install_method')
    MSpec.stub(:actions)
    MSpec.stub(:current).and_return(double("spec state").as_null_object)
  end

  after :each do
    Mock.cleanup
  end

  it "returns a MockProxy instance" do
    Mock.install_method(@mock, :method_call, :stub).should be_an_instance_of(MockProxy)
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
    @mock.method_call(:a).should == true
    Mock.install_method(@mock, :method_call, :stub).with(:a).and_return(false)
    @mock.method_call(:a).should == false
    Mock.verify_count
  end

  it "does not add to the expectation tally" do
    state = double("run state").as_null_object
    state.stub(:state).and_return(double("spec state"))
    MSpec.should_not_receive(:actions)
    Mock.install_method(@mock, :method_call, :stub).and_return(1)
    @mock.method_call.should == 1
  end
end

describe Mock, ".install_method" do
  before :each do
    @mock = double('install_method')
    MSpec.stub(:actions)
    MSpec.stub(:current).and_return(double("spec state").as_null_object)
  end

  after :each do
    Mock.cleanup
  end

  it "does not alias a mocked or stubbed method when installing a new mock or stub" do
    @mock.should_not respond_to(:method_call)

    Mock.install_method @mock, :method_call
    @mock.should respond_to(:method_call)
    @mock.should_not respond_to(Mock.replaced_name(@mock, :method_call))

    Mock.install_method @mock, :method_call, :stub
    @mock.should respond_to(:method_call)
    @mock.should_not respond_to(Mock.replaced_name(@mock, :method_call))
  end
end

class MockAndRaiseError < Exception; end

describe Mock, ".verify_call" do
  before :each do
    MSpec.stub(:actions)
    MSpec.stub(:current).and_return(double("spec state").as_null_object)

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
    lambda {
      Mock.verify_call @mock, :method_call, 42
    }.should raise_error(SpecExpectationNotMetError)
  end

  it "raises an SpecExpectationNotMetError when the mock method is called with arguments but expects none" do
    lambda {
      @proxy.with(:no_args)
      Mock.verify_call @mock, :method_call, "hello"
    }.should raise_error(SpecExpectationNotMetError)
  end

  it "raises an SpecExpectationNotMetError when the mock method is called with no arguments but expects some" do
    @proxy.with("hello", "beautiful", "world")
    lambda {
      Mock.verify_call @mock, :method_call
    }.should raise_error(SpecExpectationNotMetError)
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
    ScratchPad.recorded.should == true
  end

  it "does not yield a passed block when it is not expected to" do
    Mock.verify_call @mock, :method_call do
      ScratchPad.record true
    end
    ScratchPad.recorded.should == nil
  end

  it "can yield subsequently" do
    @proxy.and_yield(1).and_yield(2).and_yield(3)

    ScratchPad.record []
    Mock.verify_call @mock, :method_call do |arg|
      ScratchPad << arg
    end
    ScratchPad.recorded.should == [1, 2, 3]
  end

  it "can yield and return an expected value" do
    @proxy.and_yield(1).and_return(3)

    Mock.verify_call(@mock, :method_call) { |arg| ScratchPad.record arg }.should == 3
    ScratchPad.recorded.should == 1
  end

  it "raises an expection when it is expected to yield but no block is given" do
    @proxy.and_yield(1, 2, 3)
    lambda {
      Mock.verify_call(@mock, :method_call)
    }.should raise_error(SpecExpectationNotMetError)
  end

  it "raises an expection when it is expected to yield more arguments than the block can take" do
    @proxy.and_yield(1, 2, 3)
    lambda {
      Mock.verify_call(@mock, :method_call) {|a, b|}
    }.should raise_error(SpecExpectationNotMetError)
  end

  it "does not raise an expection when it is expected to yield to a block that can take any number of arguments" do
    @proxy.and_yield(1, 2, 3)
    expect {
      Mock.verify_call(@mock, :method_call) {|*a|}
    }.not_to raise_error
  end

  it "raises an exception when expected to" do
    @proxy.and_raise(MockAndRaiseError)
    lambda {
      Mock.verify_call @mock, :method_call
    }.should raise_error(MockAndRaiseError)
  end
end

describe Mock, ".verify_count" do
  before :each do
    MSpec.stub(:actions)
    MSpec.stub(:current).and_return(double("spec state").as_null_object)

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
    lambda { Mock.verify_count }.should raise_error(SpecExpectationNotMetError)
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
    lambda { Mock.verify_count }.should raise_error(SpecExpectationNotMetError)
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
    lambda { Mock.verify_count }.should raise_error(SpecExpectationNotMetError)
  end

  it "raises an SpecExpectationNotMetError when the mock receives more than exactly the expected number of calls" do
    @proxy.exactly(2)
    @mock.method_call
    @mock.method_call
    @mock.method_call
    lambda { Mock.verify_count }.should raise_error(SpecExpectationNotMetError)
  end
end

describe Mock, ".verify_count mixing mocks and stubs" do
  before :each do
    MSpec.stub(:actions)
    MSpec.stub(:current).and_return(double("spec state").as_null_object)

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
    @mock.method_call
    Mock.verify_count
  end

  it "verifies the calls to the mocked method when a mock is defined before a stub" do
    Mock.install_method @mock, :method_call, :mock
    Mock.install_method @mock, :method_call, :stub
    @mock.method_call
    Mock.verify_count
  end
end

describe Mock, ".cleanup" do
  before :each do
    MSpec.stub(:actions)
    MSpec.stub(:current).and_return(double("spec state").as_null_object)

    @mock = double('cleanup')
    @proxy = Mock.install_method @mock, :method_call
    @stub = Mock.install_method @mock, :method_call, :stub
  end

  after :each do
    Mock.cleanup
  end

  it "removes the mock method call if it did not override an existing method" do
    @mock.should respond_to(:method_call)

    Mock.cleanup
    @mock.should_not respond_to(:method_call)
  end

  it "removes the replaced method if the mock method overrides an existing method" do
    def @mock.already_here() :hey end
    @mock.should respond_to(:already_here)
    replaced_name = Mock.replaced_name(@mock, :already_here)
    Mock.install_method @mock, :already_here
    @mock.should respond_to(replaced_name)

    Mock.cleanup
    @mock.should_not respond_to(replaced_name)
    @mock.should respond_to(:already_here)
    @mock.already_here.should == :hey
  end

  it "removes all mock expectations" do
    Mock.mocks.should == { Mock.replaced_key(@mock, :method_call) => [@proxy] }
    Mock.cleanup
    Mock.mocks.should == {}
  end

  it "removes all stubs" do
    Mock.stubs.should == { Mock.replaced_key(@mock, :method_call) => [@stub] }
    Mock.cleanup
    Mock.stubs.should == {}
  end

  it "removes the replaced name for mocks" do
    replaced_key = Mock.replaced_key(@mock, :method_call)
    Mock.should_receive(:clear_replaced).with(replaced_key)

    replaced_name = Mock.replaced_name(@mock, :method_call)
    Mock.replaced?(replaced_name).should be_true

    Mock.cleanup
    Mock.replaced?(replaced_name).should be_false
  end
end
