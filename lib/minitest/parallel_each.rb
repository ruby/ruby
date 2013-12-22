# encoding: utf-8
######################################################################
# This file is imported from the minitest project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis.
######################################################################

##
# Provides a parallel #each that lets you enumerate using N threads.
# Use environment variable N to customize. Defaults to 2. Enumerable,
# so all the goodies come along (tho not all are wrapped yet to
# return another ParallelEach instance).

class ParallelEach
  require 'thread'
  include Enumerable

  ##
  # How many Threads to use for this parallel #each.

  N = (ENV['N'] || 2).to_i

  ##
  # Create a new ParallelEach instance over +list+.

  def initialize list
    @queue = Queue.new # *sigh*... the Queue api sucks sooo much...

    list.each { |i| @queue << i }
    N.times { @queue << nil }
  end

  def grep pattern # :nodoc:
    self.class.new super
  end

  def select(&block) # :nodoc:
    self.class.new super
  end

  alias find_all select # :nodoc:

  ##
  # Starts N threads that yield each element to your block. Joins the
  # threads at the end.

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

  def count
    [@queue.size - N, 0].max
  end

  alias_method :size, :count
end

class MiniTest::Unit
  alias _old_run_suites _run_suites

  ##
  # Runs all the +suites+ for a given +type+. Runs suites declaring
  # a test_order of +:parallel+ in parallel, and everything else
  # serial.

  def _run_suites suites, type
    parallel, serial = suites.partition { |s| s.test_order == :parallel }

    ParallelEach.new(parallel).map { |suite| _run_suite suite, type } +
     serial.map { |suite| _run_suite suite, type }
  end
end
