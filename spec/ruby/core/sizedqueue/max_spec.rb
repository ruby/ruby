require_relative '../../spec_helper'
require_relative '../../shared/sizedqueue/max'

describe "SizedQueue#max" do
  it_behaves_like :sizedqueue_max, :max, ->(n) { SizedQueue.new(n) }
end

describe "SizedQueue#max=" do
  it_behaves_like :sizedqueue_max=, :max=, ->(n) { SizedQueue.new(n) }
end
