require_relative '../../spec_helper'
require_relative '../../shared/queue/deque'

describe "SizedQueue#deq" do
  it_behaves_like :queue_deq, :deq, -> { SizedQueue.new(10) }
end
