require_relative '../../../spec_helper'
require 'thread'
require_relative '../shared/queue/closed'

ruby_version_is "2.3" do
  describe "SizedQueue#closed?" do
    it_behaves_like :queue_closed?, :closed?, -> { SizedQueue.new(10) }
  end
end
