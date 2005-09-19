# $Id$

def main
  if ARGV[0] == '-a'
    with_arity = true
    ARGV.delete_at 0
  else
    with_arity = false
  end
  extract_ids(ARGF).each do |id, arity|
    if with_arity
      puts "#{id} #{arity}"
    else
      puts id
    end
  end
end

def extract_ids(f)
  ids = {}
  f.each do |line|
    next if /\A\#\s*define\s+s?dispatch/ =~ line
    next if /ripper_dispatch/ =~ line
    if a = line.scan(/dispatch(\d)\((\w+)/)
      a.each do |arity, event|
        if ids[event]
          unless ids[event] == arity.to_i
            $stderr.puts "arity mismatch: #{event} (#{ids[event]} vs #{arity})"
            exit 1
          end
        end
        ids[event] = arity.to_i
      end
    end
  end
  ids.to_a.sort
end

main
