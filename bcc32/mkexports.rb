#!./miniruby -s

SYM = {}
objs = ARGV.collect {|s| s.tr('/', '\\')}
system("tdump -oiPUBDEF -oiPUBD32 #{objs.join(' ')} > pub.def")
sleep(1)
IO.foreach('pub.def'){|l|
  next unless /(PUBDEF|PUBD32)/ =~ l
  /'(.*?)'/ =~ l
  SYM[$1] = true
}

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
