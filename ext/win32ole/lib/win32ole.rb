require 'win32ole.so'

# re-define Thread#initialize
# bug #2618(ruby-core:27634)

TracePoint.trace(:thread_begin) {WIN32OLE.ole_initialize}
TracePoint.trace(:thread_end) {WIN32OLE.ole_uninitialize}
