# frozen_string_literal: true
require_relative 'helper'

class TestRDocI18nText < RDoc::TestCase

  def test_multiple_paragraphs
    paragraph1 = <<-PARAGRAPH.strip
RDoc produces HTML and command-line documentation for Ruby projects.  RDoc
includes the +rdoc+ and +ri+ tools for generating and displaying documentation
from the command-line.
    PARAGRAPH

    paragraph2 = <<-PARAGRAPH.strip
This command generates documentation for all the Ruby and C source
files in and below the current directory.  These will be stored in a
documentation tree starting in the subdirectory +doc+.
    PARAGRAPH

    raw = <<-RAW
#{paragraph1}

#{paragraph2}
    RAW

    expected = [
      {
        :type      => :paragraph,
        :paragraph => paragraph1,
        :line_no   => 1,
      },
      {
        :type      => :paragraph,
        :paragraph => paragraph2,
        :line_no   => 5,
      },
    ]
    assert_equal expected, extract_messages(raw)
  end

  def test_translate_multiple_paragraphs
    paragraph1 = <<-PARAGRAPH.strip
Paragraph 1.
    PARAGRAPH
    paragraph2 = <<-PARAGRAPH.strip
Paragraph 2.
    PARAGRAPH

    raw = <<-RAW
#{paragraph1}

#{paragraph2}
    RAW

    expected = <<-TRANSLATED
Paragraphe 1.

Paragraphe 2.
    TRANSLATED
    assert_equal expected, translate(raw)
  end

  def test_translate_not_translated_message
    nonexistent_paragraph = <<-PARAGRAPH.strip
Nonexistent paragraph.
    PARAGRAPH

    raw = <<-RAW
#{nonexistent_paragraph}
    RAW

    expected = <<-TRANSLATED
#{nonexistent_paragraph}
    TRANSLATED
    assert_equal expected, translate(raw)
  end

  def test_translate_keep_empty_lines
    raw = <<-RAW
Paragraph 1.




Paragraph 2.
    RAW

    expected = <<-TRANSLATED
Paragraphe 1.




Paragraphe 2.
    TRANSLATED
    assert_equal expected, translate(raw)
  end

  private

  def extract_messages(raw)
    text = RDoc::I18n::Text.new(raw)
    messages = []
    text.extract_messages do |message|
      messages << message
    end
    messages
  end

  def locale
    locale = RDoc::I18n::Locale.new('fr')
    messages = locale.instance_variable_get(:@messages)
    messages['markdown'] = 'markdown (markdown in fr)'
    messages['Hello'] = 'Bonjour (Hello in fr)'
    messages['Paragraph 1.'] = 'Paragraphe 1.'
    messages['Paragraph 2.'] = 'Paragraphe 2.'
    locale
  end

  def translate(raw)
    text = RDoc::I18n::Text.new(raw)
    text.translate(locale)
  end

end
