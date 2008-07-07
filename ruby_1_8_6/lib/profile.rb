require 'profiler'

END {
  Profiler__::print_profile(STDERR)
}
Profiler__::start_profile
