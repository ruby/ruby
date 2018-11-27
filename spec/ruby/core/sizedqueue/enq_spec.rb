require_relative '../../spec_helper'
require_relative '../../shared/queue/enque'
require_relative '../../shared/sizedqueue/enque'

describe "SizedQueue#enq" do
  it_behaves_like :queue_enq, :enq, -> { SizedQueue.new(10) }
end

describe "SizedQueue#enq" do
  it_behaves_like :sizedqueue_enq, :enq, ->(n) { SizedQueue.new(n) }
end
