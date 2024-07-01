require_relative '../../spec_helper'

describe "Thread#thread_variable?" do
  before :each do
    @t = Thread.new { }
  end

  after :each do
    @t.join
  end

  it "returns false if the thread variables do not contain 'key'" do
    @t.thread_variable_set(:a, 2)
    @t.thread_variable?(:b).should be_false
  end

  it "returns true if the thread variables contain 'key'" do
    @t.thread_variable_set(:a, 2)
    @t.thread_variable?(:a).should be_true
  end

  it "accepts String and Symbol keys interchangeably" do
    @t.thread_variable?('a').should be_false
    @t.thread_variable?(:a).should be_false

    @t.thread_variable_set(:a, 49)

    @t.thread_variable?('a').should be_true
    @t.thread_variable?(:a).should be_true
  end

  it "converts a key that is neither String nor Symbol with #to_str" do
    key = mock('key')
    key.should_receive(:to_str).and_return('a')
    @t.thread_variable_set(:a, 49)
    @t.thread_variable?(key).should be_true
  end

  it "does not raise FrozenError if the thread is frozen" do
    @t.freeze
    @t.thread_variable?(:a).should be_false
  end

  it "does not raise a TypeError if the key is neither Symbol nor String, nor responds to #to_str" do
    @t.thread_variable?(123).should be_false
  end

  it "does not try to convert the key with #to_sym" do
    key = mock('key')
    key.should_not_receive(:to_sym)
    @t.thread_variable?(key).should be_false
  end
end
