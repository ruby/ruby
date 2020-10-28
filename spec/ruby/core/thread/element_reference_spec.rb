require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Thread#[]" do
  it "gives access to thread local values" do
    th = Thread.new do
      Thread.current[:value] = 5
    end
    th.join
    th[:value].should == 5
    Thread.current[:value].should == nil
  end

  it "is not shared across threads" do
    t1 = Thread.new do
      Thread.current[:value] = 1
    end
    t2 = Thread.new do
      Thread.current[:value] = 2
    end
    [t1,t2].each {|x| x.join}
    t1[:value].should == 1
    t2[:value].should == 2
  end

  it "is accessible using strings or symbols" do
    t1 = Thread.new do
      Thread.current[:value] = 1
    end
    t2 = Thread.new do
      Thread.current["value"] = 2
    end
    [t1,t2].each {|x| x.join}
    t1[:value].should == 1
    t1["value"].should == 1
    t2[:value].should == 2
    t2["value"].should == 2
  end

  it "raises exceptions on the wrong type of keys" do
    -> { Thread.current[nil] }.should raise_error(TypeError)
    -> { Thread.current[5] }.should raise_error(TypeError)
  end
end
