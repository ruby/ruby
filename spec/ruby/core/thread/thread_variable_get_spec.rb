require_relative '../../spec_helper'

describe "Thread#thread_variable_get" do
  before :each do
    @t = Thread.new { }
  end

  after :each do
    @t.join
  end

  it "returns nil if the variable is not set" do
    @t.thread_variable_get(:a).should be_nil
  end

  it "returns the value previously set by #thread_variable_set" do
    @t.thread_variable_set(:a, 49)
    @t.thread_variable_get(:a).should == 49
  end

  it "returns a value private to self" do
    @t.thread_variable_set(:thread_variable_get_spec, 82)
    Thread.current.thread_variable_get(:thread_variable_get_spec).should be_nil
  end

  it "accepts String and Symbol keys interchangeably" do
    @t.thread_variable_set("a", 49)
    @t.thread_variable_get("a").should == 49
    @t.thread_variable_get(:a).should == 49
  end

  it "converts a key that is neither String nor Symbol with #to_str" do
    key = mock('key')
    key.should_receive(:to_str).and_return('a')
    @t.thread_variable_set(:a, 49)
    @t.thread_variable_get(key).should == 49
  end

  it "does not raise FrozenError if the thread is frozen" do
    @t.freeze
    @t.thread_variable_get(:a).should be_nil
  end

  it "raises a TypeError if the key is neither Symbol nor String when thread variables are already set" do
    @t.thread_variable_set(:a, 49)
    -> { @t.thread_variable_get(123) }.should raise_error(TypeError, "123 is not a symbol")
  end

  ruby_version_is '3.4' do
    it "raises a TypeError if the key is neither Symbol nor String when no thread variables are set" do
      -> { @t.thread_variable_get(123) }.should raise_error(TypeError, "123 is not a symbol")
    end

    it "raises a TypeError if the key is neither Symbol nor String without calling #to_sym" do
      key = mock('key')
      key.should_not_receive(:to_sym)
      -> { @t.thread_variable_get(key) }.should raise_error(TypeError, "#{key.inspect} is not a symbol")
    end
  end
end
