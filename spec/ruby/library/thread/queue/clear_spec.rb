require_relative '../../../spec_helper'
require 'thread'
require_relative '../shared/queue/clear'

describe "Thread::Queue#clear" do
  it_behaves_like :queue_clear, :clear, -> { Queue.new }

  # TODO: test for atomicity of Queue#clear
end
