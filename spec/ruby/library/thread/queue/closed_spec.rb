require_relative '../../../spec_helper'
require 'thread'
require_relative '../shared/queue/closed'

ruby_version_is "2.3" do
  describe "Queue#closed?" do
    it_behaves_like :queue_closed?, :closed?, -> { Queue.new }
  end
end
