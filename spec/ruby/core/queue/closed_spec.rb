require_relative '../../spec_helper'
require_relative '../../shared/queue/closed'

describe "Queue#closed?" do
  it_behaves_like :queue_closed?, :closed?, -> { Queue.new }
end
