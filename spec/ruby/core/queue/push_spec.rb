require_relative '../../spec_helper'
require_relative '../../shared/queue/enque'

describe "Queue#push" do
  it_behaves_like :queue_enq, :push, -> { Queue.new }
end
