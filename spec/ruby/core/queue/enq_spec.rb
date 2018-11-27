require_relative '../../spec_helper'
require_relative '../../shared/queue/enque'

describe "Queue#enq" do
  it_behaves_like :queue_enq, :enq, -> { Queue.new }
end
