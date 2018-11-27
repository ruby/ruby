require_relative '../../spec_helper'
require_relative '../../shared/queue/deque'

describe "Queue#shift" do
  it_behaves_like :queue_deq, :shift, -> { Queue.new }
end
