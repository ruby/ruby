require_relative '../../../spec_helper'
require 'thread'
require_relative '../shared/queue/deque'

describe "Thread::Queue#pop" do
  it_behaves_like :queue_deq, :pop, -> { Queue.new }
end
