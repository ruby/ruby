# Producer/consumer JSON parsing -- the "master hands a JSON string to a
# worker, worker parses it" pattern.
#
#   * MODE=ractor: the producer (main Ractor) sends each job to a worker with
#     `send(str, move: true)` -- a zero-copy ownership transfer within the
#     process. Workers parse and discard.
#   * MODE=fork: the producer writes each job to a worker's pipe -- the string
#     is copied through the kernel (pipe IPC). Workers read + parse.
#
# This is where a Ractor can BEAT a separate process: `move` avoids the IPC
# copy that fork must pay. Weak scaling: total jobs = N * REP.
#
# Needs the json extension on the load path (see README.md).
#
#   N=<workers>  REP=<jobs per worker, default 20000>  RECS=<records/doc, 50>
#   MODE=ractor|fork
#
# NOTE (MODE=ractor): the producer outruns the consumers (move is far cheaper
# than parse), so jobs pile up in worker mailboxes -- peak backlog is bounded
# only by RAM. With the defaults (N<=8) peak is < ~1 GB. If you crank REP/N/RECS
# way up, add backpressure or you will OOM.

require 'json'
N    = (ENV['N']    || 1).to_i
REP  = (ENV['REP']  || 20000).to_i
RECS = (ENV['RECS'] || 50).to_i
MODE = ENV['MODE']  || 'ractor'
NJOBS = N * REP

rec = { "id"=>0, "name"=>"Alice Smith", "email"=>"a@example.com", "active"=>true,
        "score"=>3.14, "tags"=>["ruby","gc"],
        "address"=>{"city"=>"Tokyo","zip"=>"100-0001"} }
TEMPLATE = JSON.generate({"count"=>RECS, "users"=>(1..RECS).map{|i| rec.merge("id"=>i)}}).freeze

if MODE == 'fork'
  line = (TEMPLATE + "\n").freeze
  writers = []; pids = []
  N.times do
    r, w = IO.pipe
    pids << fork {
      w.close
      while (l = r.gets); JSON.parse(l)["count"]; end
      exit!(0)
    }
    r.close; writers << w
  end
  t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  NJOBS.times { |i| writers[i % N].write(line) }   # pipe write == kernel copy
  writers.each(&:close)                             # EOF -> workers finish
  pids.each { |p| Process.wait(p) }
else # ractor
  workers = N.times.map do
    Ractor.new { s = 0; while (j = Ractor.receive); s += JSON.parse(j)["count"]; end; s }
  end
  t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  NJOBS.times { |i| workers[i % N].send(TEMPLATE.dup, move: true) }  # zero-copy transfer
  workers.each { |w| w.send(nil) }                                   # sentinel
  workers.each(&:value)
end
printf "%.3f\n", Process.clock_gettime(Process::CLOCK_MONOTONIC) - t
