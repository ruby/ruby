def main
  invalid = false
  table = {}
  ARGF.each do |line|
    next if /\A\#\s*define\s+s?dispatch\d/ === line
    next if /ripper_dispatch\d/ === line
    line.scan(/dispatch(\d)\((\w+)/) do |num, ev|
      num = num.to_i
      if data = table[ev]
        locations, arity = data
        unless num == arity
          invalid = true
          puts "arity differ [#{ev}]: #{ARGF.lineno}->#{num}; #{locations.join(',')}->#{arity}"
        end
        locations.push ARGF.lineno
      else
        table[ev] = [[ARGF.lineno], num.to_i]
      end
    end
  end
  exit 1 if invalid
end

main
