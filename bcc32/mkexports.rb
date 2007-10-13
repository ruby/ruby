#!./miniruby -s

$name = $library = $description = nil

SYM = {}
STDIN.reopen(open("nul"))
ARGV.each do |obj|
  IO.foreach("|tdump -q -oiPUBDEF -oiPUBD32 #{obj.tr('/', '\\')}") do |l|
    next unless /(?:PUBDEF|PUBD32)/ =~ l
    SYM[$1] = !$2 if /'(.*?)'\s+Segment:\s+_(TEXT)?/ =~ l
  end
end

exports = []
if $name
  exports << "Name " + $name
elsif $library
  exports << "Library " + $library
end
exports << "Description " + $description.dump if $description
exports << "EXPORTS"
SYM.sort.each do |sym, is_data|
  exports << (is_data ? "#{sym} DATA" : sym)
end

if $output
  open($output, 'w') {|f| f.puts exports.join("\n")}
else
  puts exports.join("\n")
end
