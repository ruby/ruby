unless defined? Thread
  fail "Thread not available for this ruby interpreter"
end

require 'thread.so'
