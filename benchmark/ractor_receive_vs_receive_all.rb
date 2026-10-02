# Compares Ractor#receive with Ractor#receive_all on 1M records.
#
# Every scenario pre-loads the queue completely before the consumer starts,
# and times only the drain.  The send side is identical for both methods --
# producers use Ractor#send either way -- so timing it would hide what
# receive_all actually optimizes: the receive side.  With the queue loaded,
# receive drains it with 1M method calls while receive_all does it in a
# handful of calls.
#
# * backlog fixnums: the main ractor loads 1M immediate values.
# * backlog strings: the main ractor loads 1M copied string payloads.
# * backlog N producers: 4 and 8 senders race to load 1M string payloads;
#   the drain sees the same 1M messages either way.  The `shared` variants
#   send the same shape through Ractor.make_shareable instead: shareable
#   payloads travel by reference, so the drain allocates nothing.
#
# Run with the locally built ruby:
#
#   ./miniruby -I./lib -I. -I.ext/common ./tool/runruby.rb --extout=.ext -- \
#     benchmark/ractor_receive_vs_receive_all.rb

require 'benchmark'

Warning[:experimental] = false

RECORDS = 1_000_000

# Payloads are passed into producer ractors, so their `self` must be
# shareable: defining the lambdas as module functions gives them a shareable
# self, which Ractor.make_shareable then accepts.
module Payloads
  def self.fixnum
    ->(i) { i }
  end

  def self.strings
    ->(i) { "message #{i}" }
  end

  def self.frozen
    ->(i) { "message #{i}".freeze } # shareable: no copy, no materialize
  end

  def self.shareable
    # A compound payload that is not shareable on its own; Ractor.make_shareable
    # turns it into one, so it travels by reference like the frozen strings.
    ->(i) { Ractor.make_shareable(['message', i]) }
  end
end

fixnum    = Ractor.make_shareable(Payloads.fixnum)
strings   = Ractor.make_shareable(Payloads.strings)
frozen    = Ractor.make_shareable(Payloads.frozen)
shareable = Ractor.make_shareable(Payloads.shareable)

# The consumer owns a port, hands it to the main ractor, and waits for :go
# while the senders fill the queue.  Only the drain is timed.
def drain(mode, payload, producers: nil)
  r = Ractor.new(mode, RECORDS) do |mode, n|
    port = Ractor::Port.new
    Ractor.main << port
    Ractor.receive # wait first message, in other case ractor will destroyed before start
    if mode == :once
      n.times { port.receive }
    else
      received = 0
      while received < n
        received += port.receive_all.length
      end
    end
  end
  port = Ractor.receive

  if producers
    senders = producers.times.map do
      Ractor.new(port, RECORDS / producers, payload) do |p, count, payload|
        count.times { |i| p << payload.call(i) }
      end
    end
    senders.each(&:value)
  else
    RECORDS.times { |i| port << payload.call(i) }
  end

  r << :go
  elapsed = Benchmark.realtime { r.value }
  [elapsed, RECORDS / elapsed]
end

def report(label, once, all)
  puts format("%-27s receive %7.2fs %10.0f/s   receive_all %7.2fs %10.0f/s   x%.2f",
              label, once[0], once[1], all[0], all[1], once[0] / all[0])
end

[
  ["backlog fixnums",            ->(m) { drain(m, fixnum) }],
  ["backlog frozen strings",     ->(m) { drain(m, frozen) }],
  ["backlog strings",            ->(m) { drain(m, strings) }],
  ["backlog 4 producers",        ->(m) { drain(m, strings, producers: 4) }],
  ["backlog 8 producers",        ->(m) { drain(m, strings, producers: 8) }],
  ["backlog 4 producers shared", ->(m) { drain(m, shareable, producers: 4) }],
  ["backlog 8 producers shared", ->(m) { drain(m, shareable, producers: 8) }],
].each do |label, scenario|
  GC.start
  once = scenario.call(:once)
  GC.start
  all = scenario.call(:all)
  report(label, once, all)
end
