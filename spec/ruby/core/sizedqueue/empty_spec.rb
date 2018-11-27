require_relative '../../spec_helper'
require_relative '../../shared/queue/empty'

describe "SizedQueue#empty?" do
  it_behaves_like :queue_empty?, :empty?, -> { SizedQueue.new(10) }
end
