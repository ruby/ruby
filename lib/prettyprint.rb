# $Id$

=begin
= PrettyPrint
The class implements pretty printing algorithm.
It finds line breaks and nice indentations for grouped structure.

By default, the class assumes that primitive elements are strings and
each byte in the strings have single column in width.
But it can be used for other situasions
by giving suitable arguments for some methods:
newline object and space generation block for (({PrettyPrint.new})),
optional width argument for (({PrettyPrint#text})),
(({PrettyPrint#breakable})), etc.
There are several candidates to use them:
text formatting using proportional fonts,
multibyte characters which has columns diffrent to number of bytes,
non-string formatting, etc.

== class methods
--- PrettyPrint.new(output[, maxwidth[, newline]]) [{|width| ...}]
    creates a buffer for pretty printing.

    ((|output|)) is a output target.  It should have a (({<<})) method 
    which accepts
    the first argument ((|obj|)) of (({PrettyPrint#text})),
    the first argument ((|sep|)) of (({PrettyPrint#breakable})),
    the first argument ((|newline|)) of (({PrettyPrint.new})),
    and
    the result of a given block for (({PrettyPrint.new})). 

    ((|maxwidth|)) specifies maximum line length.
    If it is not specified, 79 is assumed.
    However actual outputs may overflow ((|maxwidth|)) if
    long non-breakable texts are provided.

    ((|newline|)) is used for line breaks.
    (({"\n"})) is used if it is not specified.

    The block is used to generate spaces.
    (({{|width| ' ' * width}})) is used if it is not given.

== methods
--- text(obj[, width])
    adds ((|obj|)) as a text of ((|width|)) columns in width.

    If ((|width|)) is not specified, (({((|obj|)).length})) is used.

--- breakable([sep[, width]])
    tells "you can break a line here if necessary", and a
    ((|width|))-column text ((|sep|)) is inserted if a line is not
    broken at the point.

    If ((|sep|)) is not specified, (({" "})) is used.

    If ((|width|)) is not specified, (({((|sep|)).length})) is used.
    You will have to specify this when ((|sep|)) is a multibyte
    character, for example.

--- nest(indent) {...}
    increases left margin after newline with ((|indent|)) for line breaks added
    in the block.

--- group {...}
    groups line break hints added in the block.
    The line break hints are all to be breaked or not.

--- flush
    outputs buffered data.

== Bugs
* Current API is for minimalists.  More useful methods are required.

* Box based formatting?  Other (better) model/algorithm?

== References
Christian Lindig, Strictly Pretty, March 2000,
((<URL:http://www.gaertner.de/~lindig/papers/strictly-pretty.html>))

Philip Wadler, A prettier printer, March 1998,
((<URL:http://cm.bell-labs.com/cm/cs/who/wadler/topics/recent.html#prettier>))

=end

class PrettyPrint
  def initialize(output, maxwidth=79, newline="\n", &genspace)
    @output = output
    @maxwidth = maxwidth
    @newline = newline
    @genspace = genspace || lambda {|n| ' ' * n}

    @output_width = 0
    @buffer_width = 0
    @buffer = []

    root_group = Group.new(0)
    @group_stack = [root_group]
    @group_queue = GroupQueue.new(root_group)
    @indent = 0
  end

  def break_outmost_groups
    while @maxwidth < @output_width + @buffer_width
      return unless group = @group_queue.deq
      until group.breakables.empty?
	data = @buffer.shift
	@output_width = data.output(@output, @output_width, @newline, @genspace)
	@buffer_width -= data.width
      end
      while !@buffer.empty? && Text === @buffer.first
	text = @buffer.shift
	@output_width = text.output(@output, @output_width)
	@buffer_width -= text.width
      end
    end
  end

  def text(obj, width=obj.length)
    if @buffer.empty?
      @output << obj
      @output_width += width
    else
      text = @buffer.last
      unless Text === text
        text = Text.new
	@buffer << text
      end
      text.add(obj, width)
      @buffer_width += width
      break_outmost_groups
    end
  end

  def breakable(sep=' ', width=sep.length)
    group = @group_stack.last
    if group.break?
      flush
      @output << @newline
      @output << @genspace.call(@indent)
      @output_width = @indent
      @buffer_width = 0
    else
      @buffer << Breakable.new(sep, width, @indent, group)
      @buffer_width += width
      break_outmost_groups
    end
  end

  def group
    group = Group.new(@group_stack.last.depth + 1)
    @group_stack.push group
    @group_queue.enq group
    begin
      yield
    ensure
      @group_stack.pop
    end
  end

  def nest(indent)
    @indent += indent
    begin
      yield
    ensure
      @indent -= indent
    end
  end

  def flush
    @buffer.each {|data|
      @output_width = data.output(@output, @output_width, @newline, @genspace)
    }
    @buffer.clear
    @buffer_width = 0
  end

  class Text
    def initialize
      @objs = []
      @width = 0
    end
    attr_reader :width

    def output(out, output_width, newline=nil, genspace=nil)
      @objs.each {|obj| out << obj}
      output_width + @width
    end

    def add(obj, width)
      @objs << obj
      @width += width
    end
  end

  class Breakable
    def initialize(sep, width, indent, group)
      @obj = sep
      @width = width
      @indent = indent
      @group = group
      @group.breakables.push self
    end
    attr_reader :obj, :width, :indent

    def output(out, output_width, newline, genspace)
      @group.breakables.shift
      if @group.break?
	out << newline
	out << genspace.call(@indent)
	@indent
      else
	out << @obj
	output_width + @width
      end
    end
  end

  class Group
    def initialize(depth)
      @depth = depth
      @breakables = []
      @break = false
    end
    attr_reader :depth, :breakables

    def break
      @break = true
    end

    def break?
      @break
    end
  end

  class GroupQueue
    def initialize(*groups)
      @queue = []
      groups.each {|g| enq g}
    end

    def enq(group)
      depth = group.depth
      @queue << [] until depth < @queue.length
      @queue[depth] << group
    end

    def deq
      @queue.each {|gs|
	(gs.length-1).downto(0) {|i|
	  unless gs[i].breakables.empty?
	    group = gs.slice!(i, 1).first
	    group.break
	    return group
	  end
	}
	gs.each {|group| group.break}
	gs.clear
      }
      return nil
    end
  end
end

if __FILE__ == $0
  require 'runit/testcase'
  require 'runit/cui/testrunner'

  class WadlerExample < RUNIT::TestCase
    def setup
      @tree = Tree.new("aaaa", Tree.new("bbbbb", Tree.new("ccc"),
						 Tree.new("dd")),
			       Tree.new("eee"),
			       Tree.new("ffff", Tree.new("gg"),
						Tree.new("hhh"),
						Tree.new("ii")))
    end

    def hello(width)
      out = ''
      hello = PrettyPrint.new(out, width)
      hello.group {
	hello.group {
	  hello.group {
	    hello.group {
	      hello.text 'hello'
	      hello.breakable; hello.text 'a'}
	    hello.breakable; hello.text 'b'}
	  hello.breakable; hello.text 'c'}
	hello.breakable; hello.text 'd'}
      hello.flush
      out
    end

    def test_hello_00_06
      expected = <<'End'.chomp
hello
a
b
c
d
End
      assert_equal(expected, hello(0))
      assert_equal(expected, hello(6))
    end

    def test_hello_07_08
      expected = <<'End'.chomp
hello a
b
c
d
End
      assert_equal(expected, hello(7))
      assert_equal(expected, hello(8))
    end

    def test_hello_09_10
      expected = <<'End'.chomp
hello a b
c
d
End
      out = hello(9); assert_equal(expected, out)
      out = hello(10); assert_equal(expected, out)
    end

    def test_hello_11_12
      expected = <<'End'.chomp
hello a b c
d
End
      assert_equal(expected, hello(11))
      assert_equal(expected, hello(12))
    end

    def test_hello_13
      expected = <<'End'.chomp
hello a b c d
End
      assert_equal(expected, hello(13))
    end

    def tree(width)
      out = ''
      pp = PrettyPrint.new(out, width)
      @tree.show(pp)
      pp.flush
      out
    end

    def test_tree_00_19
      expected = <<'End'.chomp
aaaa[bbbbb[ccc,
           dd],
     eee,
     ffff[gg,
          hhh,
          ii]]
End
      assert_equal(expected, tree(0))
      assert_equal(expected, tree(19))
    end

    def test_tree_20_22
      expected = <<'End'.chomp
aaaa[bbbbb[ccc, dd],
     eee,
     ffff[gg,
          hhh,
          ii]]
End
      assert_equal(expected, tree(20))
      assert_equal(expected, tree(22))
    end

    def test_tree_23_43
      expected = <<'End'.chomp
aaaa[bbbbb[ccc, dd],
     eee,
     ffff[gg, hhh, ii]]
End
      assert_equal(expected, tree(23))
      assert_equal(expected, tree(43))
    end

    def test_tree_44
      assert_equal(<<'End'.chomp, tree(44))
aaaa[bbbbb[ccc, dd], eee, ffff[gg, hhh, ii]]
End
    end

    def tree_alt(width)
      out = ''
      pp = PrettyPrint.new(out, width)
      @tree.altshow(pp)
      pp.flush
      out
    end

    def test_tree_alt_00_18
      expected = <<'End'.chomp
aaaa[
  bbbbb[
    ccc,
    dd
  ],
  eee,
  ffff[
    gg,
    hhh,
    ii
  ]
]
End
      assert_equal(expected, tree_alt(0))
      assert_equal(expected, tree_alt(18))
    end

    def test_tree_alt_19_20
      expected = <<'End'.chomp
aaaa[
  bbbbb[ ccc, dd ],
  eee,
  ffff[
    gg,
    hhh,
    ii
  ]
]
End
      assert_equal(expected, tree_alt(19))
      assert_equal(expected, tree_alt(20))
    end

    def test_tree_alt_20_49
      expected = <<'End'.chomp
aaaa[
  bbbbb[ ccc, dd ],
  eee,
  ffff[ gg, hhh, ii ]
]
End
      assert_equal(expected, tree_alt(21))
      assert_equal(expected, tree_alt(49))
    end

    def test_tree_alt_50
      expected = <<'End'.chomp
aaaa[ bbbbb[ ccc, dd ], eee, ffff[ gg, hhh, ii ] ]
End
      assert_equal(expected, tree_alt(50))
    end

    class Tree
      def initialize(string, *children)
        @string = string
	@children = children
      end

      def show(pp)
	pp.group {
	  pp.text @string
	  pp.nest(@string.length) {
	    unless @children.empty?
	      pp.text '['
	      pp.nest(1) {
		first = true
		@children.each {|t|
		  if first
		    first = false
		  else
		    pp.text ','
		    pp.breakable
		  end
		  t.show(pp)
		}
	      }
	      pp.text ']'
	    end
	  }
	}
      end

      def altshow(pp)
	pp.group {
	  pp.text @string
	  unless @children.empty?
	    pp.text '['
	    pp.nest(2) {
	      pp.breakable
	      first = true
	      @children.each {|t|
		if first
		  first = false
		else
		  pp.text ','
		  pp.breakable
		end
		t.altshow(pp)
	      }
	    }
	    pp.breakable
	    pp.text ']'
	  end
	}
      end

    end
  end

  class StrictPrettyExample < RUNIT::TestCase
    def prog(width)
      out = ''
      pp = PrettyPrint.new(out, width)
      pp.group {
	pp.group {pp.nest(2) {
		     pp.text "if"; pp.breakable;
		     pp.group {
		       pp.nest(2) {
			 pp.group {pp.text "a"; pp.breakable; pp.text "=="}
			 pp.breakable; pp.text "b"}}}}
	pp.breakable
	pp.group {pp.nest(2) {
		     pp.text "then"; pp.breakable;
		     pp.group {
		       pp.nest(2) {
			 pp.group {pp.text "a"; pp.breakable; pp.text "<<"}
			 pp.breakable; pp.text "2"}}}}
	pp.breakable
	pp.group {pp.nest(2) {
		     pp.text "else"; pp.breakable;
		     pp.group {
		       pp.nest(2) {
			 pp.group {pp.text "a"; pp.breakable; pp.text "+"}
			 pp.breakable; pp.text "b"}}}}}
      pp.flush
      out
    end

    def test_00_04
      expected = <<'End'.chomp
if
  a
    ==
    b
then
  a
    <<
    2
else
  a
    +
    b
End
      assert_equal(expected, prog(0))
      assert_equal(expected, prog(4))
    end

    def test_05
      expected = <<'End'.chomp
if
  a
    ==
    b
then
  a
    <<
    2
else
  a +
    b
End
      assert_equal(expected, prog(5))
    end

    def test_06
      expected = <<'End'.chomp
if
  a ==
    b
then
  a <<
    2
else
  a +
    b
End
      assert_equal(expected, prog(6))
    end

    def test_07
      expected = <<'End'.chomp
if
  a ==
    b
then
  a <<
    2
else
  a + b
End
      assert_equal(expected, prog(7))
    end

    def test_08
      expected = <<'End'.chomp
if
  a == b
then
  a << 2
else
  a + b
End
      assert_equal(expected, prog(8))
    end

    def test_09
      expected = <<'End'.chomp
if a == b
then
  a << 2
else
  a + b
End
      assert_equal(expected, prog(9))
    end

    def test_10
      expected = <<'End'.chomp
if a == b
then
  a << 2
else a + b
End
      assert_equal(expected, prog(10))
    end

    def test_11_31
      expected = <<'End'.chomp
if a == b
then a << 2
else a + b
End
      assert_equal(expected, prog(11))
      assert_equal(expected, prog(15))
      assert_equal(expected, prog(31))
    end

    def test_32
      expected = <<'End'.chomp
if a == b then a << 2 else a + b
End
      assert_equal(expected, prog(32))
    end

  end

  class TailGroup < RUNIT::TestCase
    def test_1
      out = ''
      pp = PrettyPrint.new(out, 10)
      pp.group {
	pp.group {
	  pp.text "abc"
	  pp.breakable
	  pp.text "def"
	}
	pp.group {
	  pp.text "ghi"
	  pp.breakable
	  pp.text "jkl"
	}
      }
      pp.flush
      assert_equal("abc defghi\njkl", out)
    end
  end

  class NonString < RUNIT::TestCase
    def format(width)
      out = []
      pp = PrettyPrint.new(out, width, 'newline') {|n| "#{n} spaces"}
      pp.text(3, 3)
      pp.breakable(1, 1)
      pp.text(3, 3)
      pp.flush
      out
    end

    def test_6
      assert_equal([3, "newline", "0 spaces", 3], format(6))
    end

    def test_7
      assert_equal([3, 1, 3], format(7))
    end

  end

  class Fill < RUNIT::TestCase
    def format(width)
      out = ''
      pp = PrettyPrint.new(out, width)
      pp.group {
        pp.text 'abc'
	pp.group { pp.breakable }
        pp.text 'def'
	pp.group { pp.breakable }
        pp.text 'ghi'
	pp.group { pp.breakable }
        pp.text 'jkl'
	pp.group { pp.breakable }
        pp.text 'mno'
	pp.group { pp.breakable }
        pp.text 'pqr'
	pp.group { pp.breakable }
        pp.text 'stu'
      }
      pp.flush
      out
    end

    def test_00_06
      expected = <<'End'.chomp
abc
def
ghi
jkl
mno
pqr
stu
End
      assert_equal(expected, format(0))
      assert_equal(expected, format(6))
    end

    def test_07_10
      expected = <<'End'.chomp
abc def
ghi jkl
mno pqr
stu
End
      assert_equal(expected, format(7))
      assert_equal(expected, format(10))
    end

    def test_11_14
      expected = <<'End'.chomp
abc def ghi
jkl mno pqr
stu
End
      assert_equal(expected, format(11))
      assert_equal(expected, format(14))
    end

    def test_15_18
      expected = <<'End'.chomp
abc def ghi jkl
mno pqr stu
End
      assert_equal(expected, format(15))
      assert_equal(expected, format(18))
    end

    def test_19_22
      expected = <<'End'.chomp
abc def ghi jkl mno
pqr stu
End
      assert_equal(expected, format(19))
      assert_equal(expected, format(22))
    end

    def test_23_26
      expected = <<'End'.chomp
abc def ghi jkl mno pqr
stu
End
      assert_equal(expected, format(23))
      assert_equal(expected, format(26))
    end

    def test_27
      expected = <<'End'.chomp
abc def ghi jkl mno pqr stu
End
      assert_equal(expected, format(27))
    end

  end

  RUNIT::CUI::TestRunner.run(WadlerExample.suite)
  RUNIT::CUI::TestRunner.run(StrictPrettyExample.suite)
  RUNIT::CUI::TestRunner.run(TailGroup.suite)
  RUNIT::CUI::TestRunner.run(NonString.suite)
  RUNIT::CUI::TestRunner.run(Fill.suite)
end
