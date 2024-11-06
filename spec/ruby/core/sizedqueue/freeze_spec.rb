require_relative '../../spec_helper'
require_relative '../../shared/queue/freeze'

describe "SizedQueue#freeze" do
  it_behaves_like :queue_freeze, :freeze, -> { SizedQueue.new(1) }
end
