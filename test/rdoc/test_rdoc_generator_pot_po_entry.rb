# frozen_string_literal: true
require 'rdoc/test_case'

class TestRDocGeneratorPOTPOEntry < RDoc::TestCase

  def test_msgid_normal
    assert_equal <<-'ENTRY', entry("Hello", {}).to_s
msgid "Hello"
msgstr ""
    ENTRY
  end

  def test_msgid_multiple_lines
    assert_equal <<-'ENTRY', entry("Hello\nWorld", {}).to_s
msgid ""
"Hello\n"
"World"
msgstr ""
    ENTRY
  end

  def test_msgid_tab
    assert_equal <<-'ENTRY', entry("Hello\tWorld", {}).to_s
msgid "Hello\tWorld"
msgstr ""
    ENTRY
  end

  def test_msgid_back_slash
    assert_equal <<-'ENTRY', entry("Hello \\ World", {}).to_s
msgid "Hello \\ World"
msgstr ""
    ENTRY
  end

  def test_msgid_double_quote
    assert_equal <<-'ENTRY', entry("Hello \"World\"!", {}).to_s
msgid "Hello \"World\"!"
msgstr ""
    ENTRY
  end

  def test_translator_comment_normal
    options = {:translator_comment => "Greeting"}
    assert_equal <<-'ENTRY', entry("Hello", options).to_s
# Greeting
msgid "Hello"
msgstr ""
    ENTRY
  end

  def test_translator_comment_multiple_lines
    options = {:translator_comment => "Greeting\nfor morning"}
    assert_equal <<-'ENTRY', entry("Hello", options).to_s
# Greeting
# for morning
msgid "Hello"
msgstr ""
    ENTRY
  end

  def test_extracted_comment_normal
    options = {:extracted_comment => "Object"}
    assert_equal <<-'ENTRY', entry("Hello", options).to_s
#. Object
msgid "Hello"
msgstr ""
    ENTRY
  end

  def test_extracted_comment_multiple_lines
    options = {:extracted_comment => "Object\nMorning#greeting"}
    assert_equal <<-'ENTRY', entry("Hello", options).to_s
#. Object
#. Morning#greeting
msgid "Hello"
msgstr ""
    ENTRY
  end

  def test_references_normal
    options = {:references => [["lib/rdoc.rb", 29]]}
    assert_equal <<-'ENTRY', entry("Hello", options).to_s
#: lib/rdoc.rb:29
msgid "Hello"
msgstr ""
    ENTRY
  end

  def test_references_multiple
    options = {:references => [["lib/rdoc.rb", 29], ["lib/rdoc/i18n.rb", 9]]}
    assert_equal <<-'ENTRY', entry("Hello", options).to_s
#: lib/rdoc.rb:29
#: lib/rdoc/i18n.rb:9
msgid "Hello"
msgstr ""
    ENTRY
  end

  def test_flags_normal
    options = {:flags => ["fuzzy"]}
    assert_equal <<-'ENTRY', entry("Hello", options).to_s
#, fuzzy
msgid "Hello"
msgstr ""
    ENTRY
  end

  def test_flags_multiple
    options = {:flags => ["fuzzy", "ruby-format"]}
    assert_equal <<-'ENTRY', entry("Hello", options).to_s
#, fuzzy,ruby-format
msgid "Hello"
msgstr ""
    ENTRY
  end

  def test_full
    options = {
      :translator_comment => "Greeting",
      :extracted_comment  => "Morning#greeting",
      :references         => [["lib/rdoc.rb", 29]],
      :flags              => ["fuzzy"],
    }
    assert_equal <<-'ENTRY', entry("Hello", options).to_s
# Greeting
#. Morning#greeting
#: lib/rdoc.rb:29
#, fuzzy
msgid "Hello"
msgstr ""
    ENTRY
  end

  private
  def entry(msgid, options)
    RDoc::Generator::POT::POEntry.new(msgid, options)
  end

end
