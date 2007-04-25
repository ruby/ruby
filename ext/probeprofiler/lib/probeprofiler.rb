
require 'probeprofiler.so'

def ProbeProfiler.print_profile
  data = ProbeProfiler.profile_data
  total = 0.0
  printf("%-60s %-8s %-7s\n", "ProbeProfile Result: Method signature", "count", "ratio")
  data.map{|k, n| total += n; [n, k]}.sort.reverse.each{|n, sig|
    #
    printf("%-60s %8d %7.2f%%\n", sig, n, 100 * n / total)
  }
  printf("%60s %8d\n", "total:", total)
end

