#
# generate-ripper_rb.rb
# Creates ripper.rb, filling in default event handlers, given a basic 
# template, the list of parser events (ids1), and a list of lexer 
# events (ids2).
#

def main
  template, ids1, ids2 = *ARGV
  File.foreach(template) do |line|
    case line
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

# Generate generic arg list depending on arity (n)
# n:: [Integer] arity of method
def argdecl( n )
  %w(a b c d e f g h i j k l m)[0, n].join(', ')
end

main
