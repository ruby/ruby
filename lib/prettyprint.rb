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
--- PrettyPrint.new([newline]) [{|width| ...}]
    creates a buffer for pretty printing.

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
    increases left margin after newline with ((|indent|)) for line breaks added in the block.

--- group {...}
    groups line break hints added in the block.

--- format(out[, width])
    outputs buffered data to ((|out|)).
    It tries to restrict the line length to ((|width|)) but it may
    overflow.

    If ((|width|)) is not specified, 79 is assumed.

    ((|out|)) must have a method named (({<<})) which accepts
    a first argument ((|obj|)) of (({PrettyPrint#text})),
    a first argument ((|sep|)) of (({PrettyPrint#breakable})),
    a first argument ((|newline|)) of (({PrettyPrint.new})),
    and
    a result of a given block for (({PrettyPrint.new})). 

== Bugs
* Line breaks in a group is constrained to whether all line break hints are
  to be breaked or not.  Maybe, non-constrained version of
  PrettyPrint#group should be provided to filling multi lines.

* Box based formatting?

== References
Strictly Pretty, Christian Lindig, March 2000,
((<URL:http://www.gaertner.de/~lindig/papers/strictly-pretty.html>))

A prettier printer, Philip Wadler, March 1998,
((<URL:http://cm.bell-labs.com/cm/cs/who/wadler/topics/recent.html#prettier>))

=end

class PrettyPrint
  def initialize(newline="\n", &genspace)
    @newline = newline
    @genspace = genspace || lambda {|n| ' ' * n}
    @buf = Group.new
    @nest = [0]
    @stack = []
  end

  def text(obj, width=obj.length)
    @buf << Text.new(obj, width)
  end

  def breakable(sep=' ', width=sep.length)
    @buf << Breakable.new(sep, width, @nest.last, @newline, @genspace)
  end

  def nest(indent)
    nest_enter(indent)
    begin
      yield
    ensure
      nest_leave
    end
  end

  def nest_enter(indent)
    @nest << @nest.last + indent
  end

  def nest_leave
    @nest.pop
  end

  def group
    group_enter
    begin
      yield
    ensure
      group_leave
    end
  end

  def group_enter
    g = Group.new
    @buf << g
    @stack << @buf
    @buf = g
  end

  def group_leave
    @buf = @stack.pop
  end

  def format(out, width=79)
    tails = [[-1, 0]]
    @buf.update_tails(tails, 0)
    @buf.multiline_output(out, 0, 0, width)
  end

  class Text
    def initialize(text, width)
      @text = text
      @width = width
    end

    def update_tails(tails, group)
      tails[-1][1] += @width
    end

    def singleline_width
      return @width
    end

    def singleline_output(out)
      out << @text
    end

    def multiline_output(out, group, margin, width)
      singleline_output(out)
      return margin + singleline_width
    end
  end

  class Breakable
    def initialize(sep, width, indent, newline, genspace)
      @sep = sep
      @width = width
      @indent = indent
      @newline = newline
      @genspace = genspace
    end

    def update_tails(tails, group)
      if group == tails[-1][0]
	tails[-2][1] += @width + tails[-1][1]
	tails[-1][1] = 0
      else
	tails[-1][1] += @width
	tails << [group, 0]
      end
    end

    def singleline_width
      return @width
    end

    def singleline_output(out)
      out << @sep
    end

    def multiline_output(out, group, margin, width)
      out << @newline
      out << @genspace.call(@indent)
      return @indent
    end
  end

  class Group
    def initialize
      @buf = []
      @singleline_width = nil
    end

    def <<(obj)
      @buf << obj
    end

    def update_tails(tails, group)
      @tail = tails.empty? ? 0 : tails[-1][1]
      len = 0
      @buf.reverse_each {|obj|
        obj.update_tails(tails, group + 1)
	len += obj.singleline_width
      }
      @singleline_width = len
      while !tails.empty? && group <= tails[-1][0]
	tails[-2][1] += tails[-1][1]
        tails.pop
      end
    end

    def singleline_width
      return @singleline_width
    end

    def singleline_output(out)
      @buf.each {|obj| obj.singleline_output(out)}
    end

    def multiline_output(out, group, margin, width)
      if margin + singleline_width + @tail <= width
	singleline_output(out)
	margin += singleline_width
      else
        @buf.each {|obj|
	  margin = obj.multiline_output(out, group + 1, margin, width)
	}
      end
      return margin
    end
  end
end

if __FILE__ == $0
  require 'runit/testcase'
  require 'runit/cui/testrunner'

  class WadlerExample < RUNIT::TestCase
    def setup
      @hello = PrettyPrint.new
      @hello.group {
	@hello.group {
	  @hello.group {
	    @hello.group {
	      @hello.text 'hello'; @hello.breakable; @hello.text 'a'
	    }
	    @hello.breakable; @hello.text 'b'
	  }
	  @hello.breakable; @hello.text 'c'
	}
	@hello.breakable; @hello.text 'd'
      }

      @tree = Tree.new("aaaa", Tree.new("bbbbb", Tree.new("ccc"),
						 Tree.new("dd")),
			       Tree.new("eee"),
			       Tree.new("ffff", Tree.new("gg"),
						Tree.new("hhh"),
						Tree.new("ii")))
    end

    def test_hello_00_06
      expected = <<'End'.chomp
hello
a
b
c
d
End
      @hello.format(out='', 0); assert_equal(expected, out)
      @hello.format(out='', 6); assert_equal(expected, out)
    end

    def test_hello_07_08
      expected = <<'End'.chomp
hello a
b
c
d
End
      @hello.format(out='', 7); assert_equal(expected, out)
      @hello.format(out='', 8); assert_equal(expected, out)
    end

    def test_hello_09_10
      expected = <<'End'.chomp
hello a b
c
d
End
      @hello.format(out='', 9); assert_equal(expected, out)
      @hello.format(out='', 10); assert_equal(expected, out)
    end

    def test_hello_11_12
      expected = <<'End'.chomp
hello a b c
d
End
      @hello.format(out='', 11); assert_equal(expected, out)
      @hello.format(out='', 12); assert_equal(expected, out)
    end

    def test_hello_13
      expected = <<'End'.chomp
hello a b c d
End
      @hello.format(out='', 13); assert_equal(expected, out)
    end

    def test_tree_00_19
      pp = PrettyPrint.new
      @tree.show(pp)
      expected = <<'End'.chomp
aaaa[bbbbb[ccc,
           dd],
     eee,
     ffff[gg,
          hhh,
          ii]]
End
      pp.format(out='', 0); assert_equal(expected, out)
      pp.format(out='', 19); assert_equal(expected, out)
    end

    def test_tree_20_22
      pp = PrettyPrint.new
      @tree.show(pp)
      expected = <<'End'.chomp
aaaa[bbbbb[ccc, dd],
     eee,
     ffff[gg,
          hhh,
          ii]]
End
      pp.format(out='', 20); assert_equal(expected, out)
      pp.format(out='', 22); assert_equal(expected, out)
    end

    def test_tree_23_43
      pp = PrettyPrint.new
      @tree.show(pp)
      expected = <<'End'.chomp
aaaa[bbbbb[ccc, dd],
     eee,
     ffff[gg, hhh, ii]]
End
      pp.format(out='', 23); assert_equal(expected, out)
      pp.format(out='', 43); assert_equal(expected, out)
    end

    def test_tree_44
      pp = PrettyPrint.new
      @tree.show(pp)
      pp.format(out='', 44)
      assert_equal(<<'End'.chomp, out)
aaaa[bbbbb[ccc, dd], eee, ffff[gg, hhh, ii]]
End
    end

    def test_tree_alt_00_18
      pp = PrettyPrint.new
      @tree.altshow(pp)
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
      pp.format(out='', 0); assert_equal(expected, out)
      pp.format(out='', 18); assert_equal(expected, out)
    end

    def test_tree_alt_19_20
      pp = PrettyPrint.new
      @tree.altshow(pp)
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
      pp.format(out='', 19); assert_equal(expected, out)
      pp.format(out='', 20); assert_equal(expected, out)
    end

    def test_tree_alt_20_49
      pp = PrettyPrint.new
      @tree.altshow(pp)
      expected = <<'End'.chomp
aaaa[
  bbbbb[ ccc, dd ],
  eee,
  ffff[ gg, hhh, ii ]
]
End
      pp.format(out='', 21); assert_equal(expected, out)
      pp.format(out='', 49); assert_equal(expected, out)
    end

    def test_tree_alt_50
      pp = PrettyPrint.new
      @tree.altshow(pp)
      expected = <<'End'.chomp
aaaa[ bbbbb[ ccc, dd ], eee, ffff[ gg, hhh, ii ] ]
End
      pp.format(out='', 50); assert_equal(expected, out)
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
    def setup
      @pp = PrettyPrint.new
      @pp.group {
	@pp.group {@pp.nest(2) {
		     @pp.text "if"; @pp.breakable;
		     @pp.group {
		       @pp.nest(2) {
			 @pp.group {@pp.text "a"; @pp.breakable; @pp.text "=="}
			 @pp.breakable; @pp.text "b"}}}}
	@pp.breakable
	@pp.group {@pp.nest(2) {
		     @pp.text "then"; @pp.breakable;
		     @pp.group {
		       @pp.nest(2) {
			 @pp.group {@pp.text "a"; @pp.breakable; @pp.text "<<"}
			 @pp.breakable; @pp.text "2"}}}}
	@pp.breakable
	@pp.group {@pp.nest(2) {
		     @pp.text "else"; @pp.breakable;
		     @pp.group {
		       @pp.nest(2) {
			 @pp.group {@pp.text "a"; @pp.breakable; @pp.text "+"}
			 @pp.breakable; @pp.text "b"}}}}}
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
      @pp.format(out='', 0); assert_equal(expected, out)
      @pp.format(out='', 4); assert_equal(expected, out)
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
      @pp.format(out='', 5); assert_equal(expected, out)
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
      @pp.format(out='', 6); assert_equal(expected, out)
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
      @pp.format(out='', 7); assert_equal(expected, out)
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
      @pp.format(out='', 8); assert_equal(expected, out)
    end

    def test_09
      expected = <<'End'.chomp
if a == b
then
  a << 2
else
  a + b
End
      @pp.format(out='', 9); assert_equal(expected, out)
    end

    def test_10
      expected = <<'End'.chomp
if a == b
then
  a << 2
else a + b
End
      @pp.format(out='', 10); assert_equal(expected, out)
    end

    def test_11_31
      expected = <<'End'.chomp
if a == b
then a << 2
else a + b
End
      @pp.format(out='', 11); assert_equal(expected, out)
      @pp.format(out='', 15); assert_equal(expected, out)
      @pp.format(out='', 31); assert_equal(expected, out)
    end

    def test_32
      expected = <<'End'.chomp
if a == b then a << 2 else a + b
End
      @pp.format(out='', 32); assert_equal(expected, out)
    end

  end

  class TailGroup < RUNIT::TestCase
    def test_1
      pp = PrettyPrint.new
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
      pp.format(out='', 10)
      assert_equal("abc\ndefghi jkl", out)
    end
  end

  class NonString < RUNIT::TestCase
    def setup
      @pp = PrettyPrint.new('newline') {|n| "#{n} spaces"}
      @pp.text(3, 3)
      @pp.breakable(1, 1)
      @pp.text(3, 3)
    end

    def test_6
      @pp.format(out=[], 6)
      assert_equal([3, "newline", "0 spaces", 3], out)
    end

    def test_7
      @pp.format(out=[], 7)
      assert_equal([3, 1, 3], out)
    end

  end

  RUNIT::CUI::TestRunner.run(WadlerExample.suite)
  RUNIT::CUI::TestRunner.run(StrictPrettyExample.suite)
  RUNIT::CUI::TestRunner.run(TailGroup.suite)
  RUNIT::CUI::TestRunner.run(NonString.suite)
end
