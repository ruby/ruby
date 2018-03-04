require_relative '../../../spec_helper'
require 'thread'
require_relative '../shared/queue/enque'
require_relative 'shared/enque'

describe "Thread::SizedQueue#<<" do
  it_behaves_like :queue_enq, :<<, -> { SizedQueue.new(10) }
end

describe "Thread::SizedQueue#<<" do
  it_behaves_like :sizedqueue_enq, :<<
end
