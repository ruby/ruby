reserved_signals = ARGV

(Signal.list.keys - reserved_signals).each do |signal|
  Signal.trap(signal, -> {})
  Signal.trap(signal, "DEFAULT")
end

puts "OK"
