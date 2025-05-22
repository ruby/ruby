require_relative '../../spec_helper'
require_relative '../../shared/queue/enque'
require_relative '../../shared/sizedqueue/enque'
require_relative '../../shared/types/rb_num2dbl_fails'

describe "SizedQueue#<<" do
  it_behaves_like :queue_enq, :<<, -> { SizedQueue.new(10) }
end

describe "SizedQueue#<<" do
  it_behaves_like :sizedqueue_enq, :<<, -> n { SizedQueue.new(n) }
end

describe "SizedQueue operations with timeout" do
  it_behaves_like :rb_num2dbl_fails, nil, -> v { q = SizedQueue.new(1); q.send(:<<, 1, timeout: v) }
end
