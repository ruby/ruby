require_relative '../../spec_helper'

describe "Thread::Queue" do
  it "is the same class as ::Queue" do
    Thread.should.const_defined?(:Queue, false)
    Thread::Queue.should.equal? ::Queue
  end
end
