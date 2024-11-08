require_relative '../../spec_helper'
require_relative '../../shared/queue/freeze'

describe "Queue#freeze" do
  it_behaves_like :queue_freeze, :freeze, -> { Queue.new }
end
