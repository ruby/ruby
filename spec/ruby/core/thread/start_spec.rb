require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/start'

describe "Thread.start" do
  describe "Thread.start" do
    it_behaves_like :thread_start, :start
  end
end
