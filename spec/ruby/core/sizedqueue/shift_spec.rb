require_relative '../../spec_helper'
require_relative '../../shared/queue/deque'

describe "SizedQueue#shift" do
  it_behaves_like :queue_deq, :shift, -> { SizedQueue.new(10) }
end
