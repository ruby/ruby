#!./miniruby -s

$name = $library = $description = nil

SYM = {}

objs = ARGV.collect {|s| s.tr('/', '\\')}
IO.foreach("|dumpbin -symbols " + objs.join(' ')) do |l|
  next if /^[0-9A-F]+ 0+ UNDEF / =~ l
  next unless l.sub!(/.*?\s(\(\)\s+)?External\s+\|\s+/, "")
  is_data = !$1
  if /^[@_](?!\w+@\d+$)/ =~ l
    next if /(?!^)@.*@/ =~ l || /@[0-9a-f]{16}$/ =~ l
    l.sub!(/^[@_]/, '')
  elsif !l.sub!(/^(\S+) \([^@?\`\']*\)$/, '\1')
    next
  end
  SYM[l.strip] = is_data
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
