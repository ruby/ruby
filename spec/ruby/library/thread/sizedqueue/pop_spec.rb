require_relative '../../../spec_helper'
require 'thread'
require_relative '../shared/queue/deque'

describe "Thread::SizedQueue#pop" do
  it_behaves_like :queue_deq, :pop, -> { SizedQueue.new(10) }
end
