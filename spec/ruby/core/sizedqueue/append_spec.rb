require_relative '../../spec_helper'
require_relative '../../shared/queue/enque'
require_relative '../../shared/sizedqueue/enque'

describe "SizedQueue#<<" do
  it_behaves_like :queue_enq, :<<, -> { SizedQueue.new(10) }
end

describe "SizedQueue#<<" do
  it_behaves_like :sizedqueue_enq, :<<, -> n { SizedQueue.new(n) }
end
