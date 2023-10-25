require_relative '../../spec_helper'
require_relative '../../shared/queue/deque'
require_relative '../../shared/types/rb_num2dbl_fails'

describe "Queue#deq" do
  it_behaves_like :queue_deq, :deq, -> { Queue.new }
end

describe "Queue operations with timeout" do
  ruby_version_is "3.2" do
    it_behaves_like :rb_num2dbl_fails, nil, -> v { q = Queue.new; q.push(1); q.deq(timeout: v) }
  end
end
