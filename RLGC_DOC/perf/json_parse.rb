# Embarrassingly-parallel JSON parsing (weak scaling).
# Each worker parses the SAME ~30 KB document REP times, on its own copy.
# No data is transferred between workers -- this isolates parse + GC scaling.
# Parsed results are discarded each iteration (parse-and-discard = GC churn),
# only the last is touched to defeat dead-code elimination.
#
# Needs the json extension on the load path; see README.md for the exact flags:
#   ruby --disable-gems -I <src>/ext/json/lib -I <build>/.ext/<arch> -I <src>/lib
#
#   N=<workers>  REP=<parses per worker, default 8000>  MODE=ractor|fork|single

require 'json'
N    = (ENV['N']   || 1).to_i
REP  = (ENV['REP'] || 8000).to_i
MODE = ENV['MODE'] || (N <= 1 ? 'single' : 'ractor')

rec = { "id"=>0, "name"=>"Alice Smith", "email"=>"alice@example.com",
        "active"=>true, "score"=>3.14159, "created"=>"2026-07-06T00:00:00Z",
        "tags"=>["ruby","gc","ractor"],
        "address"=>{"city"=>"Tokyo","zip"=>"100-0001","geo"=>[35.6895,139.6917]} }
DOC = JSON.generate({"count"=>200, "users"=>(1..200).map{|i| rec.merge("id"=>i)}}).freeze

def work(doc, rep)
  last = nil
  rep.times { last = JSON.parse(doc) }
  last["count"]
end

t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
case MODE
when 'single'
  work(DOC, REP)
when 'fork'
  pids = N.times.map { fork { work(DOC, REP); exit!(0) } }
  pids.each { |p| Process.wait(p) }
else # ractor
  rs = N.times.map { Ractor.new(DOC, REP) { |d, r| work(d, r) } }
  rs.each(&:value)
end
printf "%.3f\n", Process.clock_gettime(Process::CLOCK_MONOTONIC) - t
