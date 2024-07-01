require_relative '../../spec_helper'

describe "Thread#thread_variable_set" do
  before :each do
    @t = Thread.new { }
  end

  after :each do
    @t.join
  end

  it "returns the value set" do
    @t.thread_variable_set(:a, 2).should == 2
  end

  it "sets a value that will be returned by #thread_variable_get" do
    @t.thread_variable_set(:a, 49)
    @t.thread_variable_get(:a).should == 49
  end

  it "sets a value private to self" do
    @t.thread_variable_set(:thread_variable_get_spec, 82)
    @t.thread_variable_get(:thread_variable_get_spec).should == 82
    Thread.current.thread_variable_get(:thread_variable_get_spec).should be_nil
  end

  it "accepts String and Symbol keys interchangeably" do
    @t.thread_variable_set('a', 49)
    @t.thread_variable_get('a').should == 49

    @t.thread_variable_set(:a, 50)
    @t.thread_variable_get('a').should == 50
  end

  it "converts a key that is neither String nor Symbol with #to_str" do
    key = mock('key')
    key.should_receive(:to_str).and_return('a')
    @t.thread_variable_set(key, 49)
    @t.thread_variable_get(:a).should == 49
  end

  it "removes a key if the value is nil" do
    @t.thread_variable_set(:a, 52)
    @t.thread_variable_set(:a, nil)
    @t.thread_variable?(:a).should be_false
  end

  it "raises a FrozenError if the thread is frozen" do
    @t.freeze
    -> { @t.thread_variable_set(:a, 1) }.should raise_error(FrozenError, "can't modify frozen thread locals")
  end

  it "raises a TypeError if the key is neither Symbol nor String, nor responds to #to_str" do
    -> { @t.thread_variable_set(123, 1) }.should raise_error(TypeError, '123 is not a symbol')
  end

  it "does not try to convert the key with #to_sym" do
    key = mock('key')
    key.should_not_receive(:to_sym)
    -> { @t.thread_variable_set(key, 42) }.should raise_error(TypeError, "#{key.inspect} is not a symbol")
  end
end
