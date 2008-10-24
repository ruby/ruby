require 'rubygems'
require 'minitest/unit'
require 'rdoc/markup'
require 'rdoc/markup/to_test'

class TestRDocMarkup < MiniTest::Unit::TestCase

  def basic_conv(str)
    sm = RDoc::Markup.new
    mock = RDoc::Markup::ToTest.new
    sm.convert(str, mock)
    sm.content
  end

  def line_groups(str, expected)
    m = RDoc::Markup.new
    mock = RDoc::Markup::ToTest.new

    block = m.convert(str, mock)

    if block != expected
      rows = (0...([expected.size, block.size].max)).collect{|i|
        [expected[i]||"nil", block[i]||"nil"]
      }
      printf "\n\n%35s %35s\n", "Expected", "Got"
      rows.each {|e,g| printf "%35s %35s\n", e.dump, g.dump }
    end

    assert_equal(expected, block)
  end

  def line_types(str, expected)
    m = RDoc::Markup.new
    mock = RDoc::Markup::ToTest.new
    m.convert(str, mock)
    assert_equal(expected, m.get_line_types.map{|type| type.to_s[0,1]}.join(''))
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
                  "L1: BULLET ListItem\nl1",
                  "L1: BULLET ListItem\nl2",
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
                  "L1: BULLET ListItem\nl1 l1+",
                  "L1: BULLET ListItem\nl2",
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
                  "L1: BULLET ListItem\nl1",
                  "L2: ListStart\n",
                  "L2: BULLET ListItem\nl1.1",
                  "L2: ListEnd\n",
                  "L1: BULLET ListItem\nl2",
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
                  "L1: BULLET ListItem\nl1",
                  "L2: ListStart\n",
                  "L2: BULLET ListItem\nl1.1 text",
                  "L2: Verbatim\n  code\n    code\n",
                  "L2: Paragraph\ntext",
                  "L2: ListEnd\n",
                  "L1: BULLET ListItem\nl2",
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
                  "L1: NUMBER ListItem\nl1",
                  "L2: ListStart\n",
                  "L2: BULLET ListItem\nl1.1",
                  "L2: ListEnd\n",
                  "L1: NUMBER ListItem\nl2",
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
                  "L1: LABELED ListItem\ncat: l1",
                  "L2: ListStart\n",
                  "L2: BULLET ListItem\nl1.1",
                  "L2: ListEnd\n",
                  "L1: LABELED ListItem\ndog: l2",
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
                  "L1: LABELED ListItem\ncat: l1 continuation",
                  "L1: LABELED ListItem\ndog: l2",
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

  def test_list_alpha
    str = "a. alpha\nb. baker\nB. ALPHA\nA. BAKER"

    line_groups(str,
                [ "L1: ListStart\n",
                  "L1: LOWERALPHA ListItem\nalpha",
                  "L1: LOWERALPHA ListItem\nbaker",
                  "L1: ListEnd\n",
                  "L1: ListStart\n",
                  "L1: UPPERALPHA ListItem\nALPHA",
                  "L1: UPPERALPHA ListItem\nBAKER",
                  "L1: ListEnd\n" ])
  end

  def test_list_bullet_dash
    str = "- one\n- two\n"

    line_groups(str,
                [ "L1: ListStart\n",
                  "L1: BULLET ListItem\none",
                  "L1: BULLET ListItem\ntwo",
                  "L1: ListEnd\n" ])
  end

  def test_list_bullet_star
    str = "* one\n* two\n"

    line_groups(str,
                [ "L1: ListStart\n",
                  "L1: BULLET ListItem\none",
                  "L1: BULLET ListItem\ntwo",
                  "L1: ListEnd\n" ])
  end

  def test_list_labeled_bracket
    str = "[one] item one\n[two] item two"

    line_groups(str,
                [ "L1: ListStart\n",
                  "L1: LABELED ListItem\none: item one",
                  "L1: LABELED ListItem\ntwo: item two",
                  "L1: ListEnd\n" ])
  end

  def test_list_labeled_bracket_continued
    str = "[one]\n  item one\n[two]\n  item two"

    line_groups(str,
                [ "L1: ListStart\n",
                  "L1: LABELED ListItem\none: item one",
                  "L1: LABELED ListItem\ntwo: item two",
                  "L1: ListEnd\n" ])
  end

  def test_list_labeled_colon
    str = "one:: item one\ntwo:: item two"

    line_groups(str,
                [ "L1: ListStart\n",
                  "L1: NOTE ListItem\none:: item one",
                  "L1: NOTE ListItem\ntwo:: item two",
                  "L1: ListEnd\n" ])
  end

  def test_list_labeled_colon_continued
    str = "one::\n  item one\ntwo::\n  item two"

    line_groups(str,
                [ "L1: ListStart\n",
                  "L1: NOTE ListItem\none:: item one",
                  "L1: NOTE ListItem\ntwo:: item two",
                  "L1: ListEnd\n" ])
  end

  def test_list_nested_bullet_bullet
    str = "* one\n* two\n  * cat\n  * dog"

    line_groups(str,
                [ "L1: ListStart\n",
                  "L1: BULLET ListItem\none",
                  "L1: BULLET ListItem\ntwo",
                  "L2: ListStart\n",
                  "L2: BULLET ListItem\ncat",
                  "L2: BULLET ListItem\ndog",
                  "L2: ListEnd\n",
                  "L1: ListEnd\n" ])
  end

  def test_list_nested_labeled_bullet
    str = "[one]\n  * cat\n  * dog"

    line_groups(str,
                [ "L1: ListStart\n",
                  "L1: LABELED ListItem\none: ",
                  "L2: ListStart\n",
                  "L2: BULLET ListItem\ncat",
                  "L2: BULLET ListItem\ndog",
                  "L2: ListEnd\n",
                  "L1: ListEnd\n" ])
  end

  def test_list_nested_labeled_bullet_bullet
    str = "[one]\n  * cat\n    * dog"

    line_groups(str,
                [ "L1: ListStart\n",
                  "L1: LABELED ListItem\none: ",
                  "L2: ListStart\n",
                  "L2: BULLET ListItem\ncat",
                  "L3: ListStart\n",
                  "L3: BULLET ListItem\ndog",
                  "L3: ListEnd\n",
                  "L2: ListEnd\n",
                  "L1: ListEnd\n" ])
  end

  def test_list_nested_number_number
    str = "1. one\n1. two\n   1. cat\n   1. dog"

    line_groups(str,
                [ "L1: ListStart\n",
                  "L1: NUMBER ListItem\none",
                  "L1: NUMBER ListItem\ntwo",
                  "L2: ListStart\n",
                  "L2: NUMBER ListItem\ncat",
                  "L2: NUMBER ListItem\ndog",
                  "L2: ListEnd\n",
                  "L1: ListEnd\n" ])
  end

  def test_list_number
    str = "1. one\n2. two\n1. three"

    line_groups(str,
                [ "L1: ListStart\n",
                  "L1: NUMBER ListItem\none",
                  "L1: NUMBER ListItem\ntwo",
                  "L1: NUMBER ListItem\nthree",
                  "L1: ListEnd\n" ])
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
                  "L1: BULLET ListItem\nl1",
                  "L1: ListEnd\n",
                  "L1: ListStart\n",
                  "L1: NUMBER ListItem\nn1",
                  "L1: NUMBER ListItem\nn2",
                  "L1: ListEnd\n",
                  "L1: ListStart\n",
                  "L1: BULLET ListItem\nl2",
                  "L1: ListEnd\n",
                  "L0: Paragraph\nthe time"
                ])

  end

  def test_paragraph
    str = "paragraph\n\n*bold* paragraph\n"

    line_groups str, [
      "L0: Paragraph\nparagraph",
      "L0: BlankLine\n",
      "L0: Paragraph\n*bold* paragraph"
    ]
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

  def test_verbatim
    str = "paragraph\n  *bold* verbatim\n"

    line_groups str, [
      "L0: Paragraph\nparagraph",
      "L0: Verbatim\n  *bold* verbatim\n"
    ]
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

end

MiniTest::Unit.autorun
