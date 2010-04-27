require 'minitest/unit'
require 'rdoc/markup/formatter'

##
# Test case for creating new RDoc::Markup formatters.  See
# test/test_rdoc_markup_to_*.rb for examples.

class RDoc::Markup::FormatterTestCase < MiniTest::Unit::TestCase

  def setup
    super

    @m = RDoc::Markup.new
    @am = RDoc::Markup::AttributeManager.new
    @RM = RDoc::Markup

    @bullet_list = @RM::List.new(:BULLET,
      @RM::ListItem.new(nil, @RM::Paragraph.new('l1')),
      @RM::ListItem.new(nil, @RM::Paragraph.new('l2')))

    @label_list = @RM::List.new(:LABEL,
      @RM::ListItem.new('cat', @RM::Paragraph.new('cats are cool')),
      @RM::ListItem.new('dog', @RM::Paragraph.new('dogs are cool too')))

    @lalpha_list = @RM::List.new(:LALPHA,
      @RM::ListItem.new(nil, @RM::Paragraph.new('l1')),
      @RM::ListItem.new(nil, @RM::Paragraph.new('l2')))

    @note_list = @RM::List.new(:NOTE,
      @RM::ListItem.new('cat', @RM::Paragraph.new('cats are cool')),
      @RM::ListItem.new('dog', @RM::Paragraph.new('dogs are cool too')))

    @number_list = @RM::List.new(:NUMBER,
      @RM::ListItem.new(nil, @RM::Paragraph.new('l1')),
      @RM::ListItem.new(nil, @RM::Paragraph.new('l2')))

    @ualpha_list = @RM::List.new(:UALPHA,
      @RM::ListItem.new(nil, @RM::Paragraph.new('l1')),
      @RM::ListItem.new(nil, @RM::Paragraph.new('l2')))
  end

  def self.add_visitor_tests
    self.class_eval do
      def test_start_accepting
        @to.start_accepting

        start_accepting
      end

      def test_end_accepting
        @to.start_accepting
        @to.res << 'hi'

        end_accepting
      end

      def test_accept_blank_line
        @to.start_accepting

        @to.accept_blank_line @RM::BlankLine.new

        accept_blank_line
      end

      def test_accept_heading
        @to.start_accepting

        @to.accept_heading @RM::Heading.new(5, 'Hello')

        accept_heading
      end

      def test_accept_paragraph
        @to.start_accepting

        @to.accept_paragraph @RM::Paragraph.new('hi')

        accept_paragraph
      end

      def test_accept_verbatim
        @to.start_accepting

        @to.accept_verbatim @RM::Verbatim.new('  ', 'hi', "\n",
                                              '  ', 'world', "\n")

        accept_verbatim
      end

      def test_accept_raw
        @to.start_accepting

        @to.accept_raw @RM::Raw.new("<table>",
                                    "<tr><th>Name<th>Count",
                                    "<tr><td>a<td>1",
                                    "<tr><td>b<td>2",
                                    "</table>")

        accept_raw
      end

      def test_accept_rule
        @to.start_accepting

        @to.accept_rule @RM::Rule.new(4)

        accept_rule
      end

      def test_accept_list_item_start_bullet
        @to.start_accepting

        @to.accept_list_start @bullet_list

        @to.accept_list_item_start @bullet_list.items.first

        accept_list_item_start_bullet
      end

      def test_accept_list_item_start_label
        @to.start_accepting

        @to.accept_list_start @label_list

        @to.accept_list_item_start @label_list.items.first

        accept_list_item_start_label
      end

      def test_accept_list_item_start_lalpha
        @to.start_accepting

        @to.accept_list_start @lalpha_list

        @to.accept_list_item_start @lalpha_list.items.first

        accept_list_item_start_lalpha
      end

      def test_accept_list_item_start_note
        @to.start_accepting

        @to.accept_list_start @note_list

        @to.accept_list_item_start @note_list.items.first

        accept_list_item_start_note
      end

      def test_accept_list_item_start_number
        @to.start_accepting

        @to.accept_list_start @number_list

        @to.accept_list_item_start @number_list.items.first

        accept_list_item_start_number
      end

      def test_accept_list_item_start_ualpha
        @to.start_accepting

        @to.accept_list_start @ualpha_list

        @to.accept_list_item_start @ualpha_list.items.first

        accept_list_item_start_ualpha
      end

      def test_accept_list_item_end_bullet
        @to.start_accepting

        @to.accept_list_start @bullet_list

        @to.accept_list_item_start @bullet_list.items.first

        @to.accept_list_item_end @bullet_list.items.first

        accept_list_item_end_bullet
      end

      def test_accept_list_item_end_label
        @to.start_accepting

        @to.accept_list_start @label_list

        @to.accept_list_item_start @label_list.items.first

        @to.accept_list_item_end @label_list.items.first

        accept_list_item_end_label
      end

      def test_accept_list_item_end_lalpha
        @to.start_accepting

        @to.accept_list_start @lalpha_list

        @to.accept_list_item_start @lalpha_list.items.first

        @to.accept_list_item_end @lalpha_list.items.first

        accept_list_item_end_lalpha
      end

      def test_accept_list_item_end_note
        @to.start_accepting

        @to.accept_list_start @note_list

        @to.accept_list_item_start @note_list.items.first

        @to.accept_list_item_end @note_list.items.first

        accept_list_item_end_note
      end

      def test_accept_list_item_end_number
        @to.start_accepting

        @to.accept_list_start @number_list

        @to.accept_list_item_start @number_list.items.first

        @to.accept_list_item_end @number_list.items.first

        accept_list_item_end_number
      end

      def test_accept_list_item_end_ualpha
        @to.start_accepting

        @to.accept_list_start @ualpha_list

        @to.accept_list_item_start @ualpha_list.items.first

        @to.accept_list_item_end @ualpha_list.items.first

        accept_list_item_end_ualpha
      end

      def test_accept_list_start_bullet
        @to.start_accepting

        @to.accept_list_start @bullet_list

        accept_list_start_bullet
      end

      def test_accept_list_start_label
        @to.start_accepting

        @to.accept_list_start @label_list

        accept_list_start_label
      end

      def test_accept_list_start_lalpha
        @to.start_accepting

        @to.accept_list_start @lalpha_list

        accept_list_start_lalpha
      end

      def test_accept_list_start_note
        @to.start_accepting

        @to.accept_list_start @note_list

        accept_list_start_note
      end

      def test_accept_list_start_number
        @to.start_accepting

        @to.accept_list_start @number_list

        accept_list_start_number
      end

      def test_accept_list_start_ualpha
        @to.start_accepting

        @to.accept_list_start @ualpha_list

        accept_list_start_ualpha
      end

      def test_accept_list_end_bullet
        @to.start_accepting

        @to.accept_list_start @bullet_list

        @to.accept_list_end @bullet_list

        accept_list_end_bullet
      end

      def test_accept_list_end_label
        @to.start_accepting

        @to.accept_list_start @label_list

        @to.accept_list_end @label_list

        accept_list_end_label
      end

      def test_accept_list_end_lalpha
        @to.start_accepting

        @to.accept_list_start @lalpha_list

        @to.accept_list_end @lalpha_list

        accept_list_end_lalpha
      end

      def test_accept_list_end_number
        @to.start_accepting

        @to.accept_list_start @number_list

        @to.accept_list_end @number_list

        accept_list_end_number
      end

      def test_accept_list_end_note
        @to.start_accepting

        @to.accept_list_start @note_list

        @to.accept_list_end @note_list

        accept_list_end_note
      end

      def test_accept_list_end_ualpha
        @to.start_accepting

        @to.accept_list_start @ualpha_list

        @to.accept_list_end @ualpha_list

        accept_list_end_ualpha
      end
    end
  end

end

