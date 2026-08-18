require 'timeout'

# Shared by the ractor-local incremental marking tests in test_ractor.rb, which run
# inside assert_ractor subprocesses and load this through require_relative:.
#
# A few hundred rounds is typical; this bound means need_major_by stopped working.  Each
# round runs a minor GC, so keep the bound low enough that it trips (and reports what the
# counters were doing) well before the test's own timeout fires.
MAX_MAJOR_SETUP_ROUNDS = 2_000
# Draining a freshly started major measures ~5_000 allocations.
MAX_DRAIN_ALLOCATIONS = 2_000_000
RACTOR_WAIT_TIMEOUT = 30

MARK_HEAP_ROUNDS = 5
MARK_HEAP_OBJECTS_PER_ROUND = 20_000
MARK_STEP_MIN_SLOTS = 100

# Leave this Ractor's objspace in the middle of an incremental major mark and return the
# GC state, so the caller can assert it really got there.
def start_local_incremental_major
  EnvUtil.without_gc do
    _retained = request_local_major_gc
    GC.start(full_mark: false, immediate_mark: false)
    GC.latest_gc_info(:state)
  end
end

# Build a working set worth marking incrementally, for a caller that is about to call
# start_local_incremental_major. The caller has to hold on to the return value, it is only
# worth marking for as long as it stays reachable.
def retain_for_incremental_mark(rounds: MARK_HEAP_ROUNDS, per_round: MARK_HEAP_OBJECTS_PER_ROUND)
  EnvUtil.without_gc do
    Array.new(rounds) do
      kept = []
      (2 * per_round).times { |i| object = Object.new; kept << object if i.even? }
      # Sweeping each round separately is what leaves the partially filled pages behind.
      # One sweep at the end would find the whole set laid out in one contiguous run.
      GC.start(full_mark: false)
      kept
    end
  end
end

# Allocate until this objspace asks for a major GC, leaving nothing in progress. Returns
# the allocated objects so a caller can keep them alive across what it does next.
def request_local_major_gc
  objects = []
  rounds = 0
  until GC.latest_gc_info(:need_major_by)
    if (rounds += 1) > MAX_MAJOR_SETUP_ROUNDS
      raise "no major GC requested after #{rounds} rounds " \
            "(old_objects=#{GC.stat(:old_objects)}/#{GC.stat(:old_objects_limit)}, " \
            "oldmalloc=#{GC.stat(:oldmalloc_increase_bytes)}/#{GC.stat(:oldmalloc_increase_bytes_limit)})"
    end
    objects.append(100.times.map { '*' })
    GC.start(full_mark: false)
  end
  objects
end

# Drive the cycle in progress to completion with allocation. Returns the first state
# observed after :marking, the final one, and how many incremental mark steps the drain
# saw.
def drain_incremental_cycle
  first_change = nil
  mark_steps = 0
  marked = GC.stat(:heap_marked_slots)
  allocations = 0
  loop do
    if (allocations += 1) > MAX_DRAIN_ALLOCATIONS
      raise "incremental cycle stuck in #{GC.latest_gc_info(:state)} after #{allocations} " \
            "allocations (free_slots=#{GC.stat(:heap_free_slots)}, " \
            "marked_slots=#{GC.stat(:heap_marked_slots)})"
    end
    Object.new
    state = GC.latest_gc_info(:state)
    marked, previously_marked = GC.stat(:heap_marked_slots), marked
    mark_steps += 1 if marked - previously_marked > MARK_STEP_MIN_SLOTS
    first_change ||= state unless state == :marking
    return [first_change, state, mark_steps] if state == :none
  end
end

def finish_incremental_major
  _first_change, final, _mark_steps = drain_incremental_cycle
  final
end

# Push the mark in progress through at least `steps` incremental steps without finishing
# it, so a caller can hand off a mark that is provably in flight and has begun draining
# its roots. Raises rather than returning if the cycle ends first: a caller asking for
# this wanted a mid-mark state, and silently getting a finished one would leave whatever
# it does next testing nothing.
def advance_incremental_mark(steps: 2)
  marked = GC.stat(:heap_marked_slots)
  seen = 0
  allocations = 0
  while seen < steps
    if (allocations += 1) > MAX_DRAIN_ALLOCATIONS
      raise "only #{seen} of #{steps} mark steps after #{allocations} allocations " \
            "(marked_slots=#{GC.stat(:heap_marked_slots)})"
    end
    Object.new
    state = GC.latest_gc_info(:state)
    unless state == :marking
      raise "cycle reached #{state} after #{seen} of #{steps} mark steps: the working " \
            "set was too small to keep the mark going"
    end
    marked, previously_marked = GC.stat(:heap_marked_slots), marked
    seen += 1 if marked - previously_marked > MARK_STEP_MIN_SLOTS
  end
  GC.latest_gc_info(:state)
end

# Hold off collecting this Ractor's objspace for the duration of the block without
# ending the cycle in progress (which is what GC.disable would do). Incremental marking
# still advances on page exhaustion, what this rules out is a collection started behind
# the caller's back by the allocation or malloc accounting inside the block.
def without_local_gc
  already_disabled = Bug::GC.local_disable_no_rest
  begin
    yield
  ensure
    Bug::GC.local_enable unless already_disabled
  end
end

# Non-blocking "did the peer die while we waited" check. Ractor.select re-raises the
# peer's exception as Ractor::RemoteError, which is the answer we want to report.
def peer_death(peer)
  result = Ractor.select(peer, timeout: 0.01)
  result && "terminated early with #{result.last.inspect}"
rescue Ractor::RemoteError, Ractor::Error => e
  "terminated early: #{(e.cause || e).message}"
end

# Bounded Ractor.receive.  None of these tests send nil, so a nil return is the timeout.
# Waiting happens in slices with a liveness check between them: a peer that died gets
# reported in well under a second, while a peer that is merely slow (these handshakes
# wait on a full incremental-major setup) still gets the whole timeout.
def receive_from(peer = nil, timeout: RACTOR_WAIT_TIMEOUT)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
  slice = peer ? 0.25 : timeout
  loop do
    message = Ractor.receive(timeout: slice)
    return message unless message.nil?
    if peer and (death = peer_death(peer))
      raise "#{peer.inspect} #{death}"
    end
    break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
  end
  raise "no message received within #{timeout}s"
end

# Bounded Ractor#value.  Ractor.select reports termination and re-raises the peer's
# exception as Ractor::RemoteError, so a dead peer explains itself instead of hanging.
def value_of(ractor, timeout: RACTOR_WAIT_TIMEOUT)
  result = Ractor.select(ractor, timeout: timeout)
  raise "#{ractor.inspect} did not terminate within #{timeout}s" if result.nil?
  result.last
end

# Bound an operation whose own blocking behaviour is under test
def with_wait_bound(what, timeout: RACTOR_WAIT_TIMEOUT)
  Timeout.timeout(timeout, nil, "#{what} did not finish within #{timeout}s") { yield }
end

def wait_until_single_ractor(timeout: RACTOR_WAIT_TIMEOUT)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
  while Ractor.count != 1
    if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      raise "#{Ractor.count} Ractors still alive after #{timeout}s"
    end
    Thread.pass
  end
end

# fork, and leave the child through exit! on every path.  The child inherits
# assert_separately's at_exit, which writes a result token into the pipe the parent test
# is parsing, so an exception escaping the block would post a second <error> block and
# garble the report.  Put the failure on stderr instead, which assert_separately already
# treats as a failure, and leave without running at_exit.
def fork_child
  fork do
    begin
      yield
      exit!(0)
    rescue SystemExit => e
      exit!(e.status)
    rescue Exception => e
      STDERR.puts(e.full_message(highlight: false))
      exit!(1)
    end
  end
end

# Bounded Process.wait2
def wait_for_pid(pid, timeout: RACTOR_WAIT_TIMEOUT)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
  loop do
    if (waited = Process.waitpid2(pid, Process::WNOHANG))
      return waited.last
    end
    if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      Process.kill(:KILL, pid)
      Process.waitpid(pid)
      raise "forked child did not exit within #{timeout}s"
    end
    sleep 0.05
  end
end
