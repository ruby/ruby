require_relative '../../spec_helper'
require_relative '../../shared/queue/closed'

describe "SizedQueue#closed?" do
  it_behaves_like :queue_closed?, :closed?, -> { SizedQueue.new(10) }
end
