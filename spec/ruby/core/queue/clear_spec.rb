require_relative '../../spec_helper'
require_relative '../../shared/queue/clear'

describe "Queue#clear" do
  it_behaves_like :queue_clear, :clear, -> { Queue.new }
end
