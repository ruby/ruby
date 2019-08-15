require_relative '../../spec_helper'
require_relative '../../shared/queue/length'

describe "Queue#size" do
  it_behaves_like :queue_length, :size, -> { Queue.new }
end
