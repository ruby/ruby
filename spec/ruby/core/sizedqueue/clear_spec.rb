require_relative '../../spec_helper'
require_relative '../../shared/queue/clear'

describe "SizedQueue#clear" do
  it_behaves_like :queue_clear, :clear, -> { SizedQueue.new(10) }
end
