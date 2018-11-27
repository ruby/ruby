require_relative '../../spec_helper'
require_relative '../../shared/queue/length'

describe "SizedQueue#length" do
  it_behaves_like :queue_length, :length, -> { SizedQueue.new(10) }
end
