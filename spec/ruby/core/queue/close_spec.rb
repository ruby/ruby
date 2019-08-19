require_relative '../../spec_helper'
require_relative '../../shared/queue/close'

describe "Queue#close" do
  it_behaves_like :queue_close, :close, -> { Queue.new }
end
