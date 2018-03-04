require_relative '../../../spec_helper'
require 'thread'
require_relative '../shared/queue/deque'

describe "Thread::Queue#shift" do
  it_behaves_like :queue_deq, :shift, -> { Queue.new }
end
