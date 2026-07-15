Warning[:experimental] = false
def check(c, m); raise "FAIL: #{m}" unless c; end

# Hash with default value
r = Ractor.new { Ractor.receive }
h = Hash.new(42); h[:x] = 1
r.send(h, move: true)
hv = r.value
check(hv[:x] == 1 && hv[:missing] == 42, "hash default value lost: #{hv[:missing]}")

# Hash with default proc -> unshareable proc cannot be contained-moved: error
r = Ractor.new { Ractor.receive }
h2 = Hash.new { |hash, k| k.to_s * 2 }
h2[:a] = 9
raised = (r.send(h2, move: true); false) rescue (Ractor::Error === $! )
check(raised, "default-proc hash move should raise (proc not movable)")

# compare_by_identity hash
r = Ractor.new { Ractor.receive }
h3 = {}.compare_by_identity
k = +"key"; h3[k] = 1
r.send(h3, move: true)
h3v = r.value
check(h3v.compare_by_identity? , "compare_by_identity lost")

# shared string (substring shares buffer)
r = Ractor.new { Ractor.receive }
base = "abcdefghijklmnopqrstuvwxyz" * 10
sub = base[5..]   # may share the buffer
r.send(sub, move: true)
check(r.value == base[5..], "shared substring move corrupted")

# frozen string literal (often STR_NOFREE / fstring) inside a mutable array
r = Ractor.new { Ractor.receive }
arr = [+"mutable", "frozenlit".freeze]
r.send(arr, move: true)
av = r.value
check(av == ["mutable", "frozenlit"], "string in array corrupted: #{av.inspect}")

# big heap array (non-embedded) of strings
r = Ractor.new { Ractor.receive }
big = (0...50).map { |i| +"e#{i}" }
r.send(big, move: true)
bv = r.value
check(bv.size == 50 && bv[49] == "e49", "big array move corrupted")

# MatchData with named captures + onig (larger)
r = Ractor.new { Ractor.receive }
m = "2026-06-16".match(/(?<y>\d+)-(?<mo>\d+)-(?<d>\d+)/)
mc = m.dup
r.send(m, move: true)
mv = r.value
check(mv[:y] == "2026" && mv[:d] == "16" && mv.pre_match == "", "matchdata named captures lost: #{mv.inspect}")

puts "MOVE_EDGE_OK"
