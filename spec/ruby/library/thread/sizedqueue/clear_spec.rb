require_relative '../../../spec_helper'
require 'thread'
require_relative '../shared/queue/clear'

describe "Thread::SizedQueue#clear" do
  it_behaves_like :queue_clear, :clear, -> { SizedQueue.new(10) }

  # TODO: test for atomicity of Queue#clear
end
