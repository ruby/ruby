require 'test/unit'
require 'soap/marshal'


module SOAP
module Marshal


class Node; include SOAP::Marshallable
  attr_reader :first, :second, :str

  def initialize(*init_next)
    @first = init_next[0]
    @second = init_next[1]
  end
end

class TestDigraph < Test::Unit::TestCase
  def setup
    @n9 = Node.new
    @n81 = Node.new(@n9)
    @n82 = Node.new(@n9)
    @n7 = Node.new(@n81, @n82)
    @n61 = Node.new(@n7)
    @n62 = Node.new(@n7)
    @n5 = Node.new(@n61, @n62)
    @n41 = Node.new(@n5)
    @n42 = Node.new(@n5)
    @n3 = Node.new(@n41, @n42)
    @n21 = Node.new(@n3)
    @n22 = Node.new(@n3)
    @n1 = Node.new(@n21, @n22)
  end

  def test_marshal
    f = File.open("digraph_marshalled_string.soap", "wb")
    SOAP::Marshal.dump(@n1, f)
    f.close
    f = File.open("digraph_marshalled_string.soap")
    str = f.read
    f.close
    newnode = SOAP::Marshal.unmarshal(str)
    assert_equal(newnode.first.first.__id__, newnode.second.first.__id__)
    assert_equal(newnode.first.first.first.first.__id__, newnode.second.first.second.first.__id__)
  end

  def teardown
    if File.exist?("digraph_marshalled_string.soap")
      File.unlink("digraph_marshalled_string.soap")
    end
  end
end


end
end
