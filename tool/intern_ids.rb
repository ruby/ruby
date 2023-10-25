#!/usr/bin/ruby -sp
# $ ruby -i tool/intern_ids.rb -prefix=_ foo.c

BEGIN {
  $prefix ||= nil

  defs = File.join(File.dirname(__dir__), "defs/id.def")
  ids = eval(File.read(defs), binding, defs)
  table = {}
  ids[:predefined].each {|v, t| table[t] = "id#{v}"}
  ids[:token_op].each {|v, t, *| table[t] = "id#{v}"}
  predefined = table.keys
}

$_.gsub!(/rb_intern\("([^\"]+)"\)/) do
  token = $1
  table[token] ||= "id" + id2varname(token, $prefix)
end

END {
  predefined.each {|t| table.delete(t)}
  unless table.empty?
    table = table.sort_by {|t, v| v}

    # Append at the last, then edit and move appropriately.
    puts
    puts "==== defs"
    table.each {|t, v| puts "static ID #{v};"}
    puts ">>>>"
    puts
    puts "==== init"
    table.each {|t, v|puts "#{v} = rb_intern_const(\"#{t}\");"}
    puts ">>>>"
  end
}
