#!./miniruby -s

SYM = {}
STDIN.reopen(open("nul"))
ARGV.each do |obj|
  IO.foreach("|tdump -q -oiPUBDEF -oiPUBD32 #{obj.tr('/', '\\')}") do |l|
    next unless /(?:PUBDEF|PUBD32)/ =~ l
    SYM[$1] = true if /'(.*?)'/ =~ l
  end
end

exports = []
if $name
  exports << "Name " + $name
elsif $library
  exports << "Library " + $library
end
exports << "Description " + $description.dump if $description
exports << "EXPORTS" << SYM.keys.sort

if $output
  open($output, 'w') {|f| f.puts exports.join("\n")}
else
  puts exports.join("\n")
end
