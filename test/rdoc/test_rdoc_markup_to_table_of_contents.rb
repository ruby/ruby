require 'rdoc/test_case'

class TestRDocMarkupToTableOfContents < RDoc::Markup::FormatterTestCase

  add_visitor_tests

  def setup
    super

    @to = RDoc::Markup::ToTableOfContents.new
  end

  def end_accepting
    assert_equal %w[hi], @to.res
  end

  def empty
    assert_empty @to.res
  end

  def accept_heading
    assert_equal [@RM::Heading.new(5, 'Hello')], @to.res
  end

  def accept_heading_1
    assert_equal [@RM::Heading.new(1, 'Hello')], @to.res
  end

  def accept_heading_2
    assert_equal [@RM::Heading.new(2, 'Hello')], @to.res
  end

  def accept_heading_3
    assert_equal [@RM::Heading.new(3, 'Hello')], @to.res
  end

  def accept_heading_4
    assert_equal [@RM::Heading.new(4, 'Hello')], @to.res
  end

  def accept_heading_b
    assert_equal [@RM::Heading.new(1, '*Hello*')], @to.res
  end

  def accept_heading_suppressed_crossref
    assert_equal [@RM::Heading.new(1, '\\Hello')], @to.res
  end

  alias accept_blank_line                             empty
  alias accept_block_quote                            empty
  alias accept_document                               empty
  alias accept_list_end_bullet                        empty
  alias accept_list_end_label                         empty
  alias accept_list_end_lalpha                        empty
  alias accept_list_end_note                          empty
  alias accept_list_end_number                        empty
  alias accept_list_end_ualpha                        empty
  alias accept_list_item_end_bullet                   empty
  alias accept_list_item_end_label                    empty
  alias accept_list_item_end_lalpha                   empty
  alias accept_list_item_end_note                     empty
  alias accept_list_item_end_number                   empty
  alias accept_list_item_end_ualpha                   empty
  alias accept_list_item_start_bullet                 empty
  alias accept_list_item_start_label                  empty
  alias accept_list_item_start_lalpha                 empty
  alias accept_list_item_start_note                   empty
  alias accept_list_item_start_note_2                 empty
  alias accept_list_item_start_note_multi_description empty
  alias accept_list_item_start_note_multi_label       empty
  alias accept_list_item_start_number                 empty
  alias accept_list_item_start_ualpha                 empty
  alias accept_list_start_bullet                      empty
  alias accept_list_start_label                       empty
  alias accept_list_start_lalpha                      empty
  alias accept_list_start_note                        empty
  alias accept_list_start_number                      empty
  alias accept_list_start_ualpha                      empty
  alias accept_paragraph                              empty
  alias accept_paragraph_b                            empty
  alias accept_paragraph_br                           empty
  alias accept_paragraph_break                        empty
  alias accept_paragraph_i                            empty
  alias accept_paragraph_plus                         empty
  alias accept_paragraph_star                         empty
  alias accept_paragraph_underscore                   empty
  alias accept_raw                                    empty
  alias accept_rule                                   empty
  alias accept_verbatim                               empty
  alias list_nested                                   empty
  alias list_verbatim                                 empty
  alias start_accepting                               empty

  def test_accept_document_omit_headings_below
    document = doc
    document.omit_headings_below = 2

    @to.accept_document document

    assert_equal 2, @to.omit_headings_below
  end

  def test_accept_heading_suppressed
    @to.start_accepting
    @to.omit_headings_below = 4

    suppressed = head 5, 'Hello'

    @to.accept_heading suppressed

    assert_empty @to.res
  end

  def test_suppressed_eh
    @to.omit_headings_below = nil

    refute @to.suppressed? head(1, '')

    @to.omit_headings_below = 1

    refute @to.suppressed? head(1, '')
    assert @to.suppressed? head(2, '')
  end

end

