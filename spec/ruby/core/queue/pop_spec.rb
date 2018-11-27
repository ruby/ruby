require_relative '../../spec_helper'
require_relative '../../shared/queue/deque'

describe "Queue#pop" do
  it_behaves_like :queue_deq, :pop, -> { Queue.new }
end
