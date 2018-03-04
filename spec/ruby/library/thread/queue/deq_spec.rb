require_relative '../../../spec_helper'
require 'thread'
require_relative '../shared/queue/deque'

describe "Thread::Queue#deq" do
  it_behaves_like :queue_deq, :deq, -> { Queue.new }
end
