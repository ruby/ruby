require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Thread.main" do
  it "returns the main thread" do
    Thread.new { @main = Thread.main ; @current = Thread.current}.join
    @main.should_not == @current
    @main.should == Thread.current
  end
end
