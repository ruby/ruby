require_relative '../../spec_helper'

describe "Thread#thread_variable?" do
  before :each do
    @t = Thread.new { }
  end

  after :each do
    @t.join
  end

  it "returns false if the thread variables do not contain 'key'" do
    @t.thread_variable_set :a, 2
    @t.thread_variable?(:b).should be_false
  end

  it "returns true if the thread variables contain 'key'" do
    @t.thread_variable_set :a, 2
    @t.thread_variable?(:a).should be_true
  end
end
