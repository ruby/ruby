# frozen_string_literal: true

require_relative "compact_index"

Artifice.deactivate

class CompactIndexRateLimited < CompactIndexAPI
  class RequestCounter
    def self.queue
      @queue ||= Queue.new
    end

    def self.size
      @queue.size
    end

    def self.enq(name)
      @queue.enq(name)
    end

    def self.deq
      @queue.deq
    end
  end

  configure do
    RequestCounter.queue
  end

  get "/info/:name" do
    RequestCounter.enq(params[:name])

    begin
      if RequestCounter.size == 1
        etag_response do
          gem = gems.find {|g| g.name == params[:name] }
          CompactIndex.info(gem ? gem.versions : [])
        end
      else
        status 429
      end
    ensure
      RequestCounter.deq
    end
  end
end

Artifice.activate_with(CompactIndexRateLimited)
