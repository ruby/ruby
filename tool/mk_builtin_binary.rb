#
# make builtin_binary.inc file.
#

def dump_bin iseq
  bin = iseq.to_binary
  bin.each_byte.with_index{|b, index|
    print "\n  " if (index%20) == 0
    print "0x#{'%02x' % b.ord}, "
  }
end

ary = []
RubyVM::each_builtin{|feature, iseq|
  ary << [feature, iseq]
}

$stdout = open('builtin_binary.inc', 'wb')

ary.each{|feature, iseq|
  puts "static const unsigned char #{feature}_bin[] = {"
    dump_bin(iseq)
  puts "};"
}

puts "static const struct builtin_binary builtin_binary[] = {"
ary.each{|feature, iseq|
  puts "  {#{feature.dump}, #{feature}_bin, sizeof(#{feature}_bin)},"
}
puts "  {NULL}," # dummy sentry
puts "};"

puts "#define BUILTIN_BINARY_SIZE #{ary.size}"
