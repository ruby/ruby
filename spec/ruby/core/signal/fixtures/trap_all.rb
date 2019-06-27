cannot_be_trapped = %w[KILL STOP] # See man 2 signal

(Signal.list.keys - cannot_be_trapped).each do |signal|
  begin
    Signal.trap(signal, -> {})
  rescue ArgumentError => e
    unless /can't trap reserved signal|Signal already used by VM or OS/ =~ e.message
      raise e
    end
  else
    Signal.trap(signal, "DEFAULT")
  end
end

puts "OK"
