require_relative '../../spec_helper'
require_relative '../../shared/queue/enque'

describe "Queue#<<" do
  it_behaves_like :queue_enq, :<<, -> { Queue.new }
end
