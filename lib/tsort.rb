=begin
= tsort.rb

tsort.rb provides a module for topological sorting and
strongly connected components.

== Example

  require 'tsort'

  class Hash
    include TSort
    alias tsort_each_node each_key
    def tsort_each_child(node, &block)
      fetch(node).each(&block)
    end
  end

  {1=>[2, 3], 2=>[3], 3=>[], 4=>[]}.tsort
  #=> [3, 2, 1, 4]

  {1=>[2], 2=>[3, 4], 3=>[2], 4=>[]}.strongly_connected_components
  #=> [[4], [2, 3], [1]]

== TSort module
TSort implements topological sorting using Tarjan's algorithm for
strongly connected components.

TSort is designed to be able to use with any object which can be interpreted
as a directed graph.
TSort requires two methods to interpret a object as a graph:
tsort_each_node and tsort_each_child.

* tsort_each_node is used to iterate for all nodes over a graph.
* tsort_each_child is used to iterate for child nodes of a given node.

The equality of nodes are defined by eql? and hash since
TSort uses Hash internally.

=== methods
--- tsort 
    returns a topologically sorted array of nodes.
    The array is sorted from children to parents:
    I.e. the first element has no child and the last node has no parent.

    If there is a cycle, (({TSort::Cyclic})) is raised.

--- tsort_each {|node| ...}
    is the iterator version of the (({tsort})) method.
    (({((|obj|)).tsort_each})) is similar to (({((|obj|)).tsort.each})) but
    modification of ((|obj|)) during the iteration may cause unexpected result.

    (({tsort_each})) returns (({nil})).
    If there is a cycle, (({TSort::Cyclic})) is raised.

--- strongly_connected_components
    returns strongly connected components as an array of array of nodes.
    The array is sorted from children to parents.
    Each elements of the array represents a strongly connected component.

--- each_strongly_connected_component {|nodes| ...}
    is the iterator version of the (({strongly_connected_components})) method.
    (({((|obj|)).each_strongly_connected_component})) is similar to
    (({((|obj|)).strongly_connected_components.each})) but
    modification of ((|obj|)) during the iteration may cause unexpected result.

    (({each_strongly_connected_component})) returns (({nil})).

--- each_strongly_connected_component_from(node) {|nodes| ...}
    iterates over strongly connected component in the subgraph reachable from 
    ((|node|)).

    Return value is unspecified.

    (({each_strongly_connected_component_from})) doesn't call
    (({tsort_each_node})).

--- tsort_each_node {|node| ...}
    should be implemented by a extended class.

    (({tsort_each_node})) is used to iterate for all nodes over a graph.

--- tsort_each_child(node) {|child| ...}
    should be implemented by a extended class.

    (({tsort_each_child})) is used to iterate for child nodes of ((|node|)).

== More Realistic Example
Very simple `make' like tool can be implemented as follows:

  require 'tsort'

  class Make
    def initialize
      @dep = {}
      @dep.default = []
    end

    def rule(outputs, inputs=[], &block)
      triple = [outputs, inputs, block]
      outputs.each {|f| @dep[f] = [triple]}
      @dep[triple] = inputs
    end

    def build(target)
      each_strongly_connected_component_from(target) {|ns|
        if ns.length != 1
          fs = ns.delete_if {|n| Array === n}
          raise TSort::Cyclic.new("cyclic dependencies: #{fs.join ', '}")
        end
        n = ns.first
        if Array === n
          outputs, inputs, block = n
          inputs_time = inputs.map {|f| File.mtime f}.max
          begin
            outputs_time = outputs.map {|f| File.mtime f}.min
          rescue Errno::ENOENT
            outputs_time = nil
          end
          if outputs_time == nil ||
             inputs_time != nil && outputs_time <= inputs_time
            sleep 1 if inputs_time != nil && inputs_time.to_i == Time.now.to_i
            block.call
          end
        end
      }
    end

    def tsort_each_child(node, &block)
      @dep[node].each(&block)
    end
    include TSort
  end

  def command(arg)
    print arg, "\n"
    system arg
  end

  m = Make.new
  m.rule(%w[t1]) { command 'date > t1' }
  m.rule(%w[t2]) { command 'date > t2' }
  m.rule(%w[t3]) { command 'date > t3' }
  m.rule(%w[t4], %w[t1 t3]) { command 'cat t1 t3 > t4' }
  m.rule(%w[t5], %w[t4 t2]) { command 'cat t4 t2 > t5' }
  m.build('t5')

== Bugs

* (('tsort.rb')) is wrong name because this library uses
  Tarjan's algorithm for strongly connected components.
  Although (('strongly_connected_components.rb')) is correct but too long,

== References
R. E. Tarjan, 
Depth First Search and Linear Graph Algorithms,
SIAM Journal on Computing, Vol. 1, No. 2, pp. 146-160, June 1972.

#@Article{Tarjan:1972:DFS,
#  author =       "R. E. Tarjan",
#  key =          "Tarjan",
#  title =        "Depth First Search and Linear Graph Algorithms",
#  journal =      j-SIAM-J-COMPUT,
#  volume =       "1",
#  number =       "2",
#  pages =        "146--160",
#  month =        jun,
#  year =         "1972",
#  CODEN =        "SMJCAT",
#  ISSN =         "0097-5397 (print), 1095-7111 (electronic)",
#  bibdate =      "Thu Jan 23 09:56:44 1997",
#  bibsource =    "Parallel/Multi.bib, Misc/Reverse.eng.bib",
#}
=end

module TSort
  class Cyclic < StandardError
  end

  def tsort
    result = []
    tsort_each {|element| result << element}
    result
  end

  def tsort_each
    each_strongly_connected_component {|component|
      if component.size == 1
        yield component.first
      else
        raise Cyclic.new("topological sort failed: #{component.inspect}")
      end
    }
  end

  def strongly_connected_components
    result = []
    each_strongly_connected_component {|component| result << component}
    result
  end

  def each_strongly_connected_component(&block)
    id_map = {}
    stack = []
    tsort_each_node {|node|
      unless id_map.include? node
        each_strongly_connected_component_from(node, id_map, stack, &block)
      end
    }
    nil
  end

  def each_strongly_connected_component_from(node, id_map={}, stack=[], &block)
    minimum_id = node_id = id_map[node] = id_map.size
    stack_length = stack.length
    stack << node

    tsort_each_child(node) {|child|
      if id_map.include? child
        child_id = id_map[child]
        minimum_id = child_id if child_id && child_id < minimum_id
      else
        sub_minimum_id =
          each_strongly_connected_component_from(child, id_map, stack, &block)
        minimum_id = sub_minimum_id if sub_minimum_id < minimum_id
      end
    }

    if node_id == minimum_id
      component = stack.slice!(stack_length .. -1)
      component.each {|n| id_map[n] = nil}
      yield component
    end

    minimum_id
  end

  def tsort_each_node
    raise NotImplementedError.new
  end

  def tsort_each_child(node)
    raise NotImplementedError.new
  end
end

if __FILE__ == $0
  require 'runit/testcase'
  require 'runit/cui/testrunner'

  class Hash
    include TSort
    alias tsort_each_node each_key
    def tsort_each_child(node, &block)
      fetch(node).each(&block)
    end
  end

  class Array
    include TSort
    alias tsort_each_node each_index
    def tsort_each_child(node, &block)
      fetch(node).each(&block)
    end
  end

  class TSortTest < RUNIT::TestCase
    def test_dag
      h = {1=>[2, 3], 2=>[3], 3=>[]}
      assert_equal([3, 2, 1], h.tsort)
      assert_equal([[3], [2], [1]], h.strongly_connected_components)
    end

    def test_cycle
      h = {1=>[2], 2=>[3, 4], 3=>[2], 4=>[]}
      assert_equal([[4], [2, 3], [1]],
        h.strongly_connected_components.map {|nodes| nodes.sort})
      assert_exception(TSort::Cyclic) { h.tsort }
    end

    def test_array
      a = [[1], [0], [0], [2]]
      assert_equal([[0, 1], [2], [3]],
        a.strongly_connected_components.map {|nodes| nodes.sort})

      a = [[], [0]]
      assert_equal([[0], [1]],
        a.strongly_connected_components.map {|nodes| nodes.sort})
    end
  end

  RUNIT::CUI::TestRunner.run(TSortTest.suite)
end

