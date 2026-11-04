require_relative '../../spec_helper'

describe "ENV.[]=" do
  before :each do
    @saved_foo = ENV["foo"]
  end

  after :each do
    ENV["foo"] = @saved_foo
  end

  it "sets the environment variable to the given value" do
    ENV["foo"] = "bar"
    ENV["foo"].should == "bar"
  end

  it "returns the value" do
    value = "bar"
    ENV.send(:[]=, "foo", value).should.equal?(value)
  end

  it "deletes the environment variable when the value is nil" do
    ENV["foo"] = "bar"
    ENV["foo"] = nil
    ENV.key?("foo").should == false
  end

  platform_is_not :windows do
    it "accepts a BINARY variable name containing non-ASCII bytes" do
      key = "ENV_ELEMENT_SET_SPEC_\u00DCBER"
      begin
        ENV[key.b] = "bar"
        ENV[key].should == "bar"
      ensure
        ENV[key] = nil
      end
    end
  end

  it "coerces the key argument with #to_str" do
    k = mock("key")
    k.should_receive(:to_str).and_return("foo")
    ENV[k] = "bar"
    ENV["foo"].should == "bar"
  end

  it "coerces the value argument with #to_str" do
    v = mock("value")
    v.should_receive(:to_str).and_return("bar")
    ENV["foo"] = v
    ENV["foo"].should == "bar"
  end

  it "raises TypeError when the key is not coercible to String" do
    -> { ENV[Object.new] = "bar" }.should.raise(TypeError, "no implicit conversion of Object into String")
  end

  it "raises TypeError when the value is not coercible to String" do
    -> { ENV["foo"] = Object.new }.should.raise(TypeError, "no implicit conversion of Object into String")
  end

  it "raises Errno::EINVAL when the key contains the '=' character" do
    -> { ENV["foo="] = "bar" }.should.raise(Errno::EINVAL)
  end

  it "raises Errno::EINVAL when the key is an empty string" do
    -> { ENV[""] = "bar" }.should.raise(Errno::EINVAL)
  end

  it "does nothing when the key is not a valid environment variable key and the value is nil" do
    ENV["foo="] = nil
    ENV.key?("foo=").should == false
  end

  it "supports concurrent access from multiple threads" do
    n_threads = 8
    n = 200
    keys = Array.new(10) { |i| "ENV_ELEMENT_SET_SPEC_THREAD_SAFETY_#{i}" }

    begin
      # This reproduces the pattern of Bundler.with_unbundled_env called
      # concurrently: threads repeatedly mutate the environment and replace it
      # with a snapshot.
      start = Queue.new
      go = Queue.new
      threads = Array.new(n_threads) do |t|
        Thread.new do
          start << true
          go.pop
          n.times do |i|
            key = keys[(i + t) % keys.size]
            ENV[key] = "value"
            ENV[key]
            ENV.each { nil }
            ENV.replace(ENV.to_hash)
            ENV.delete(key) if i % 3 == 0
          end
        end
      end
      n_threads.times { start.pop }
      n_threads.times { go << true }
      threads.each(&:join)

      # ENV must remain consistent: every key it reports must still be
      # readable from the process environment.
      ENV.size.should == ENV.keys.size
      ENV.keys.each do |key|
        ENV[key].should_not == nil
      end
    ensure
      keys.each { |key| ENV.delete(key) }
    end
  end
end
