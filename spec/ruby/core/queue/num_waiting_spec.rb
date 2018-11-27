require_relative '../../spec_helper'
require_relative '../../shared/queue/num_waiting'

describe "Queue#num_waiting" do
  it_behaves_like :queue_num_waiting, :num_waiting, -> { Queue.new }
end
