require_relative '../../spec_helper'
require_relative '../../shared/queue/length'

describe "SizedQueue#size" do
  it_behaves_like :queue_length, :size, -> { SizedQueue.new(10) }
end
