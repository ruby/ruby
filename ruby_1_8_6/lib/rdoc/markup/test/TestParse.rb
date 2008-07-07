require 'test/unit'

$:.unshift "../../.."

require 'rdoc/markup/simple_markup'

include SM

class TestParse < Test::Unit::TestCase

  class MockOutput
    def start_accepting
      @res = []
      end
    
    def end_accepting
      @res
    end

    def accept_paragraph(am, fragment)
      @res << fragment.to_s
    end

    def accept_verbatim(am, fragment)
      @res << fragment.to_s
    end

    def accept_list_start(am, fragment)
      @res << fragment.to_s
    end

    def accept_list_end(am, fragment)
      @res << fragment.to_s
    end

    def accept_list_item(am, fragment)
      @res << fragment.to_s
    end

    def accept_blank_line(am, fragment)
      @res << fragment.to_s
    end

    def accept_heading(am, fragment)
      @res << fragment.to_s
    end

    def accept_rule(am, fragment)
      @res << fragment.to_s
    end

  end

  def basic_conv(str)
    sm = SimpleMarkup.new
    mock = MockOutput.new
    sm.convert(str, mock)
    sm.content
  end

  def line_types(str, expected)
    p = SimpleMarkup.new
    mock = MockOutput.new
    p.convert(str, mock)
    assert_equal(expected, p.get_line_types.map{|type| type.to_s[0,1]}.join(''))
  end

  def line_groups(str, expected)
    p = SimpleMarkup.new
    mock = MockOutput.new

    block = p.convert(str, mock)

    if block != expected
      rows = (0...([expected.size, block.size].max)).collect{|i|
        [expected[i]||"nil", block[i]||"nil"] 
      }
      printf "\n\n%35s %35s\n", "Expected", "Got"
      rows.each {|e,g| printf "%35s %35s\n", e.dump, g.dump }
    end

    assert_equal(expected, block)
  end

  def test_tabs
    str = "hello\n  dave"
    assert_equal(str, basic_conv(str))
    str = "hello\n\tdave"
    assert_equal("hello\n        dave", basic_conv(str))
    str = "hello\n \tdave"
    assert_equal("hello\n        dave", basic_conv(str))
    str = "hello\n  \tdave"
    assert_equal("hello\n        dave", basic_conv(str))
    str = "hello\n   \tdave"
    assert_equal("hello\n        dave", basic_conv(str))
    str = "hello\n    \tdave"
    assert_equal("hello\n        dave", basic_conv(str))
    str = "hello\n     \tdave"
    assert_equal("hello\n        dave", basic_conv(str))
    str = "hello\n      \tdave"
    assert_equal("hello\n        dave", basic_conv(str))
    str = "hello\n       \tdave"
    assert_equal("hello\n        dave", basic_conv(str))
    str = "hello\n        \tdave"
    assert_equal("hello\n                dave", basic_conv(str))
    str = ".\t\t."
    assert_equal(".               .", basic_conv(str))
  end

  def test_whitespace
    assert_equal("hello", basic_conv("hello"))
    assert_equal("hello", basic_conv(" hello "))
    assert_equal("hello", basic_conv(" \t \t hello\t\t"))

    assert_equal("1\n 2\n  3", basic_conv("1\n 2\n  3"))
    assert_equal("1\n 2\n  3", basic_conv("  1\n   2\n    3"))

    assert_equal("1\n 2\n  3\n1\n 2", basic_conv("1\n 2\n  3\n1\n 2"))
    assert_equal("1\n 2\n  3\n1\n 2", basic_conv("  1\n   2\n    3\n  1\n   2"))

    assert_equal("1\n 2\n\n  3", basic_conv("  1\n   2\n\n    3"))
  end

  def test_types
    str = "now is the time"
    line_types(str, 'P')

    str = "now is the time\nfor all good men"
    line_types(str, 'PP')

    str = "now is the time\n  code\nfor all good men"
    line_types(str, 'PVP')

    str = "now is the time\n  code\n more code\nfor all good men"
    line_types(str, 'PVVP')

    str = "now is\n---\nthe time"
    line_types(str, 'PRP')

    str = %{\
       now is
       * l1
       * l2
       the time}
    line_types(str, 'PLLP')

    str = %{\
       now is
       * l1
         l1+
       * l2
       the time}
    line_types(str, 'PLPLP')

    str = %{\
       now is
       * l1
         * l1.1
       * l2
       the time}
    line_types(str, 'PLLLP')

    str = %{\
       now is
       * l1
         * l1.1
           text
             code
             code

           text
       * l2
       the time}
    line_types(str, 'PLLPVVBPLP')

    str = %{\
       now is
       1. l1
          * l1.1
       2. l2
       the time}
    line_types(str, 'PLLLP')

    str = %{\
       now is
       [cat] l1
             * l1.1
       [dog] l2
       the time}
    line_types(str, 'PLLLP')

    str = %{\
       now is
       [cat] l1
             continuation
       [dog] l2
       the time}
    line_types(str, 'PLPLP')
  end

  def test_groups
    str = "now is the time"
    line_groups(str, ["L0: Paragraph\nnow is the time"] )

    str = "now is the time\nfor all good men"
    line_groups(str, ["L0: Paragraph\nnow is the time for all good men"] )

    str = %{\
      now is the time
        code _line_ here
      for all good men}

    line_groups(str,
                [ "L0: Paragraph\nnow is the time",
                  "L0: Verbatim\n  code _line_ here\n",
                  "L0: Paragraph\nfor all good men"
                ] )

    str = "now is the time\n  code\n more code\nfor all good men"
    line_groups(str,
                [ "L0: Paragraph\nnow is the time",
                  "L0: Verbatim\n  code\n more code\n",
                  "L0: Paragraph\nfor all good men"
                ] )

    str = %{\
       now is
       * l1
       * l2
       the time}
    line_groups(str,
                [ "L0: Paragraph\nnow is",
                  "L1: ListStart\n",
                  "L1: ListItem\nl1",
                  "L1: ListItem\nl2",
                  "L1: ListEnd\n",
                  "L0: Paragraph\nthe time"
                ])

    str = %{\
       now is
       * l1
         l1+
       * l2
       the time}
    line_groups(str,
                [ "L0: Paragraph\nnow is",
                  "L1: ListStart\n",
                  "L1: ListItem\nl1 l1+",
                  "L1: ListItem\nl2",
                  "L1: ListEnd\n",
                  "L0: Paragraph\nthe time"
                ])

    str = %{\
       now is
       * l1
         * l1.1
       * l2
       the time}
    line_groups(str,
                [ "L0: Paragraph\nnow is",
                  "L1: ListStart\n",
                  "L1: ListItem\nl1",
                  "L2: ListStart\n",
                  "L2: ListItem\nl1.1",
                  "L2: ListEnd\n",
                  "L1: ListItem\nl2",
                  "L1: ListEnd\n",
                  "L0: Paragraph\nthe time"
                ])


    str = %{\
       now is
       * l1
         * l1.1
           text
             code
               code

           text
       * l2
       the time}
    line_groups(str,
                [ "L0: Paragraph\nnow is",
                  "L1: ListStart\n",
                  "L1: ListItem\nl1",
                  "L2: ListStart\n",
                  "L2: ListItem\nl1.1 text",
                  "L2: Verbatim\n  code\n    code\n",
                  "L2: Paragraph\ntext",
                  "L2: ListEnd\n",
                  "L1: ListItem\nl2",
                  "L1: ListEnd\n",
                  "L0: Paragraph\nthe time"
                ])


    str = %{\
       now is
       1. l1
          * l1.1
       2. l2
       the time}
    line_groups(str,
                [ "L0: Paragraph\nnow is",
                  "L1: ListStart\n",
                  "L1: ListItem\nl1",
                  "L2: ListStart\n",
                  "L2: ListItem\nl1.1",
                  "L2: ListEnd\n",
                  "L1: ListItem\nl2",
                  "L1: ListEnd\n",
                  "L0: Paragraph\nthe time"
                ])

    str = %{\
       now is
       [cat] l1
             * l1.1
       [dog] l2
       the time}
    line_groups(str,
                [ "L0: Paragraph\nnow is",
                  "L1: ListStart\n",
                  "L1: ListItem\nl1",
                  "L2: ListStart\n",
                  "L2: ListItem\nl1.1",
                  "L2: ListEnd\n",
                  "L1: ListItem\nl2",
                  "L1: ListEnd\n",
                  "L0: Paragraph\nthe time"
                ])

    str = %{\
       now is
       [cat] l1
             continuation
       [dog] l2
       the time}
    line_groups(str,
                [ "L0: Paragraph\nnow is",
                  "L1: ListStart\n",
                  "L1: ListItem\nl1 continuation",
                  "L1: ListItem\nl2",
                  "L1: ListEnd\n",
                  "L0: Paragraph\nthe time"
                ])

    
  end

  def test_verbatim_merge
    str = %{\
       now is
          code
       the time}

    line_groups(str,
                [ "L0: Paragraph\nnow is",
                  "L0: Verbatim\n   code\n",
                  "L0: Paragraph\nthe time"
                ])


    str = %{\
       now is
          code
          code1
       the time}

    line_groups(str,
                [ "L0: Paragraph\nnow is",
                  "L0: Verbatim\n   code\n   code1\n",
                  "L0: Paragraph\nthe time"
                ])


    str = %{\
       now is
          code

          code1
       the time}

    line_groups(str,
                [ "L0: Paragraph\nnow is",
                  "L0: Verbatim\n   code\n\n   code1\n",
                  "L0: Paragraph\nthe time"
                ])


    str = %{\
       now is
          code

          code1

       the time}

    line_groups(str,
                [ "L0: Paragraph\nnow is",
                  "L0: Verbatim\n   code\n\n   code1\n",
                  "L0: Paragraph\nthe time"
                ])


    str = %{\
       now is
          code

          code1

          code2
       the time}

    line_groups(str,
                [ "L0: Paragraph\nnow is",
                  "L0: Verbatim\n   code\n\n   code1\n\n   code2\n",
                  "L0: Paragraph\nthe time"
                ])


    # Folds multiple blank lines
    str = %{\
       now is
          code


          code1

       the time}

    line_groups(str,
                [ "L0: Paragraph\nnow is",
                  "L0: Verbatim\n   code\n\n   code1\n",
                  "L0: Paragraph\nthe time"
                ])


  end
 
  def test_list_split
    str = %{\
       now is
       * l1
       1. n1
       2. n2
       * l2
       the time}
    line_groups(str,
                [ "L0: Paragraph\nnow is",
                  "L1: ListStart\n",
                  "L1: ListItem\nl1",
                  "L1: ListEnd\n",
                  "L1: ListStart\n",
                  "L1: ListItem\nn1",
                  "L1: ListItem\nn2",
                  "L1: ListEnd\n",
                  "L1: ListStart\n",
                  "L1: ListItem\nl2",
                  "L1: ListEnd\n",
                  "L0: Paragraph\nthe time"
                ])

  end


  def test_headings
    str = "= heading one"
    line_groups(str, 
                [ "L0: Heading\nheading one"
                ])

    str = "=== heading three"
    line_groups(str, 
                [ "L0: Heading\nheading three"
                ])

    str = "text\n   === heading three"
    line_groups(str, 
                [ "L0: Paragraph\ntext",
                  "L0: Verbatim\n   === heading three\n"
                ])

    str = "text\n   code\n   === heading three"
    line_groups(str, 
                [ "L0: Paragraph\ntext",
                  "L0: Verbatim\n   code\n   === heading three\n"
                ])

    str = "text\n   code\n=== heading three"
    line_groups(str, 
                [ "L0: Paragraph\ntext",
                  "L0: Verbatim\n   code\n",
                  "L0: Heading\nheading three"
                ])

  end

  
end
