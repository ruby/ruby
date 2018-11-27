require_relative '../../spec_helper'
require_relative '../../shared/queue/close'

describe "SizedQueue#close" do
  it_behaves_like :queue_close, :close, -> { SizedQueue.new(10) }
end
