case RUBY_PLATFORM
when /darwin/
  ok = true
when /mswin/, /mingw/
  func = "GetProcessMemoryInfo(0, 0, 0)"
  hdr = "psapi.h"
  ok = have_func(func, hdr) || have_library("psapi", func, hdr)
end

if ok
  create_makefile("-test-/memory_status")
end
