require_relative '../../../spec_helper'
require 'thread'
require_relative '../shared/queue/close'

ruby_version_is "2.3" do
  describe "SizedQueue#close" do
    it_behaves_like :queue_close, :close, -> { SizedQueue.new(10) }
  end
end
