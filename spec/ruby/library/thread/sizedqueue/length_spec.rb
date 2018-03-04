require_relative '../../../spec_helper'
require 'thread'
require_relative '../shared/queue/length'

describe "Thread::SizedQueue#length" do
  it_behaves_like :queue_length, :length, -> { SizedQueue.new(10) }
end
