require 'soap/marshal'

class Node; include SOAP::Marshallable
  attr_reader :first, :second, :str

  def initialize(*init_next)
    @first = init_next[0]
    @second = init_next[1]
  end
end

n9 = Node.new
n81 = Node.new(n9)
n82 = Node.new(n9)
n7 = Node.new(n81, n82)
n61 = Node.new(n7)
n62 = Node.new(n7)
n5 = Node.new(n61, n62)
n41 = Node.new(n5)
n42 = Node.new(n5)
n3 = Node.new(n41, n42)
n21 = Node.new(n3)
n22 = Node.new(n3)
n1 = Node.new(n21, n22)

File.open("digraph_marshalled_string.soap", "wb") do |f|
  SOAP::Marshal.dump(n1, f)
end

marshalledString = File.open("digraph_marshalled_string.soap") { |f| f.read }

puts marshalledString

newnode = SOAP::Marshal.unmarshal(marshalledString)

puts newnode.inspect

p newnode.first.first.__id__
p newnode.second.first.__id__
p newnode.first.first.first.first.__id__
p newnode.second.first.second.first.__id__

File.unlink("digraph_marshalled_string.soap")
