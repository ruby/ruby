# encoding: utf-8
######################################################################
# This file is imported from the minitest project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis.
######################################################################

class ParallelEach
  require 'thread'
  include Enumerable

  N = (ENV['N'] || 2).to_i

  def initialize list
    @queue = Queue.new # *sigh*... the Queue api sucks sooo much...

    list.each { |i| @queue << i }
    N.times { @queue << nil }
  end

  def grep pattern
    self.class.new super
  end

  def each
    threads = N.times.map {
      Thread.new do
        Thread.current.abort_on_exception = true
        while job = @queue.pop
          yield job
        end
      end
    }
    threads.map(&:join)
  end
end
