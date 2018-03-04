require_relative '../../../spec_helper'
require 'thread'
require_relative '../shared/queue/enque'

describe "Thread::Queue#enq" do
  it_behaves_like :queue_enq, :enq, -> { Queue.new }
end
