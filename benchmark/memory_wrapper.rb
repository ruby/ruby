
write_file, target, script_file = ARGV

load(script_file)
require_relative '../test/lib/memory_status'
open(write_file, 'wb'){|f|
  ms = Memory::Status.new
  case target.to_sym
  when :peak
    key = ms.respond_to?(:hwm) ? :hwm : :peak
  when :size
    key = ms.respond_to?(:rss) ? :rss : :size
  end

  f.puts ms[key]
}
