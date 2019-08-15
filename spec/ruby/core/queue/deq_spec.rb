require_relative '../../spec_helper'
require_relative '../../shared/queue/deque'

describe "Queue#deq" do
  it_behaves_like :queue_deq, :deq, -> { Queue.new }
end
