require_relative '../../../spec_helper'
require 'thread'
require_relative '../shared/queue/length'

describe "Thread::SizedQueue#size" do
  it_behaves_like :queue_length, :size, -> { SizedQueue.new(10) }
end
