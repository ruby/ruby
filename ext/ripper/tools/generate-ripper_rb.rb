# $Id$

def main
  template, ids1, ids2 = *ARGV
  File.foreach(template) do |line|
    case line
    when /\A\#include ids1/
      print_items read_ids(ids1)
    when /\A\#include ids2/
      print_items read_ids(ids2)
    when /\A\#include handlers1/
      File.foreach(ids1) do |line|
        id, arity = line.split
        arity = arity.to_i
        puts
        puts "  def on__#{id}(#{argdecl(arity)})"
        puts "    #{arity == 0 ? 'nil' : 'a'}"
        puts "  end"
      end
    when /\A\#include handlers2/
      File.foreach(ids2) do |line|
        id, arity = line.split
        arity = arity.to_i
        puts
        puts "  def on__#{id}(token)"
        puts "    token"
        puts "  end"
      end
    when /\A\#include (.*)/
      raise "unknown operation: #include #{$1}"
    else
      print line
    end
  end
end

def print_items(ids)
  comma = "\n"
  ids.each do |id|
    print comma; comma = ",\n"
    print "    #{id.intern.inspect}"
  end
  puts
end

def read_ids(path)
  File.readlines(path).map {|line| line.split[0] }
end

def argdecl(n)
  %w(a b c d e f g h i j k l m)[0, n].join(', ')
end

main
