#
# make builtin_binary.inc file.
#

def dump_bin iseq
  bin = iseq.to_binary
  bin.each_byte.with_index{|b, index|
    print "\n " if (index%20) == 0
    print " 0x#{'%02x' % b.ord},"
  }
  print "\n"
end

$stdout = open('builtin_binary.inc', 'wb')

puts <<H
// -*- c -*-
// DO NOT MODIFY THIS FILE DIRECTLY.
// auto-generated file by #{File.basename(__FILE__)}

H

if ARGV.include?('--cross=yes')
  # do nothing
else
  ary = []
  RubyVM::each_builtin{|feature, iseq|
    ary << [feature, iseq]
  }

  ary.each{|feature, iseq|
    print "\n""static const unsigned char #{feature}_bin[] = {"
    dump_bin(iseq)
    puts "};"
  }

  print "\n""static const struct builtin_binary builtin_binary[] = {\n"
  ary.each{|feature, iseq|
    puts "  {#{feature.dump}, #{feature}_bin, sizeof(#{feature}_bin)},"
  }
  puts "  {NULL}," # dummy sentry
  puts "};"
  puts "#define BUILTIN_BINARY_SIZE #{ary.size}"
end
