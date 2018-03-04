require_relative '../../../spec_helper'
require 'thread'
require_relative '../shared/queue/empty'

describe "Thread::Queue#empty?" do
  it_behaves_like :queue_empty?, :empty?, -> { Queue.new }
end
