require_relative '../../spec_helper'

describe "Thread::SizedQueue" do
  it "is the same class as ::SizedQueue" do
    Thread.should have_constant(:SizedQueue)
    Thread::SizedQueue.should equal ::SizedQueue
  end
end
