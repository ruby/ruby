require_relative '../../spec_helper'

describe "Thread::Queue" do
  it "is the same class as ::Queue" do
    Thread.should have_constant(:Queue)
    Thread::Queue.should equal ::Queue
  end
end
