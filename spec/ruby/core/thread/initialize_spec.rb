require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Thread#initialize" do

  describe "already initialized" do

    before do
      @t = Thread.new { sleep }
    end

    after do
      @t.kill
      @t.join
    end

    it "raises a ThreadError" do
      -> {
        @t.instance_eval do
          initialize {}
        end
      }.should raise_error(ThreadError)
    end

  end

end
