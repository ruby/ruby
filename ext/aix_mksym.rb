
data = []
IO.foreach("|/usr/ccs/bin/nm -p #{ARGV[0]}") do |line|
  line = line.split
  case line[1]
  when "B", "D"
    data << line[0]
  end
end
data.uniq!
data.sort!
open(ARGV[1], "w") {|exp| exp.puts "#!", data}
