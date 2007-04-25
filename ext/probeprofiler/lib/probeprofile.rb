require 'probeprofiler'
END{
  ProbeProfiler.stop_profile
  ProbeProfiler.print_profile
}

ProbeProfiler.start_profile
