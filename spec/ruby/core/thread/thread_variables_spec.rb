require File.expand_path('../../../spec_helper', __FILE__)

describe "Thread#thread_variables" do
  before :each do
    @t = Thread.new { }
  end

  after :each do
    @t.join
  end

  it "returns the keys of all the values set" do
    @t.thread_variable_set :a, 2
    @t.thread_variable_set :b, 4
    @t.thread_variable_set :c, 6
    @t.thread_variables.sort.should == [:a, :b, :c]
  end

  it "sets a value private to self" do
    @t.thread_variable_set :a, 82
    @t.thread_variable_set :b, 82
    Thread.current.thread_variables.should_not include(:a, :b)
  end

  it "only contains user thread variables and is empty initially" do
    Thread.current.thread_variables.should == []
    @t.thread_variables.should == []
  end
end
