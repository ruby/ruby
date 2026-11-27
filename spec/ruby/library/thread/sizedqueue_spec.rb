require_relative '../../spec_helper'

describe "Thread::SizedQueue" do
  it "is the same class as ::SizedQueue" do
    Thread.should.const_defined?(:SizedQueue, false)
    Thread::SizedQueue.should.equal? ::SizedQueue
  end
end
