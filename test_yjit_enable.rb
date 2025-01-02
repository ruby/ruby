# Memory in MiB

yjit_enabled_before = RubyVM::YJIT.enabled?
puts("YJIT enabled before computation: #{yjit_enabled_before}")

RubyVM::YJIT.enable(stats: false, call_threshold: 5)
# RubyVM::YJIT.enable(stats: false)

def fib(n)
  return n if n < 2

  fib(n - 1) + fib(n - 2)
end

result = fib(10)

yjit_enabled_after = RubyVM::YJIT.enabled?
puts("YJIT enabled after computation: #{yjit_enabled_after}")

# Output the results
puts("Result of fib computation: #{result}")
code_region_size = RubyVM::YJIT.runtime_stats[:code_region_size]
code_region_size_mib = code_region_size / 1_048_576.to_f
puts("YJIT-SUMMARY code_region_size: #{code_region_size}")
