require_relative '../../spec_helper'
require_relative '../../shared/queue/empty'

describe "Queue#empty?" do
  it_behaves_like :queue_empty?, :empty?, -> { Queue.new }
end
