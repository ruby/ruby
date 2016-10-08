case RUBY_PLATFORM
when /darwin/
  ok = true
end

if ok
  create_makefile("-test-/memory_status")
end
