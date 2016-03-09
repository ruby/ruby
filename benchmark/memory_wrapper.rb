
write_file, target, script_file = ARGV

load(script_file)
require_relative '../test/lib/memory_status'
open(write_file, 'wb'){|f|
  ms = Memory::Status.new
  case target.to_sym
  when :peak
    key = ms.member?(:hwm) ? :hwm : :peak
  when :size
    key = ms.member?(:rss) ? :rss : :size
  end

  f.puts ms[key]
}
