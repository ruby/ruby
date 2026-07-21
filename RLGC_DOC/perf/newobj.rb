# Single-Ractor allocation microbenchmark, for `perf stat`.
# Isolates the per-object allocation (newobj) cost.
#
#   CNT=<allocations, default 20_000_000>
#   GC=off   -> GC.disable, objects kept alive in an array (pure newobj + page
#               allocation, no sweep)
#   GC=on    -> default (newobj + real GC/sweep); this is the mode where
#               RLGCv2's extra per-page sweep work shows up
#   BASE=1   -> empty loop only (subtract from GC=off to get pure cycles/alloc)
#
# Example (pure newobj cost per allocation):
#   c_alloc=$(CNT=30000000 GC=off perf stat -e cycles ruby newobj.rb ...)
#   c_base=$( CNT=30000000 BASE=1 perf stat -e cycles ruby newobj.rb ...)
#   (c_alloc - c_base) / 30000000  => cycles per Object.new

n = (ENV['CNT'] || 20_000_000).to_i

if ENV['BASE'] == '1'
  i = 0; while i < n; i += 1; end
elsif ENV['GC'] == 'off'
  GC.disable
  a = Array.new(n)
  i = 0; while i < n; a[i] = Object.new; i += 1; end
else
  i = 0; while i < n; Object.new; i += 1; end
end
