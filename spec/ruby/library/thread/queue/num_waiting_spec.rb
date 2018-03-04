require_relative '../../../spec_helper'
require 'thread'
require_relative '../shared/queue/num_waiting'

describe "Thread::Queue#num_waiting" do
  it_behaves_like :queue_num_waiting, :num_waiting, -> { Queue.new }
end
