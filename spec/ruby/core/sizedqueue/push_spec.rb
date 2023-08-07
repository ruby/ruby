require_relative '../../spec_helper'
require_relative '../../shared/queue/enque'
require_relative '../../shared/sizedqueue/enque'
require_relative '../../shared/types/rb_num2dbl_fails'

describe "SizedQueue#push" do
  it_behaves_like :queue_enq, :push, -> { SizedQueue.new(10) }
end

describe "SizedQueue#push" do
  it_behaves_like :sizedqueue_enq, :push, -> n { SizedQueue.new(n) }
end

describe "SizedQueue operations with timeout" do
  ruby_version_is "3.2" do
    it_behaves_like :rb_num2dbl_fails, nil, -> v { q = SizedQueue.new(1); q.push(1, timeout: v) }
  end
end
