require 'fileutils'
require 'tmpdir'
require 'rubygems'
require 'minitest/unit'

require 'rdoc/generator/texinfo'

# From chapter 18 of the Pickaxe 3rd ed. and the TexInfo manual.
class TestRDocInfoFormatting < MiniTest::Unit::TestCase
  def setup
    @output_dir = File.join Dir.mktmpdir("test_rdoc_"), "info_formatting"
    @output_file = File.join @output_dir, 'rdoc.texinfo'

    RDoc::RDoc.new.document(['--fmt=texinfo', '--quiet',
                             File.expand_path(__FILE__),
                             "--op=#{@output_dir}"])
    @text = File.read @output_file

    # File.open('rdoc.texinfo', 'w') { |f| f.puts @text }
  end

  def teardown
    FileUtils.rm_rf File.dirname(@output_dir)
  end

  # Make sure tags like *this* do not make HTML
  def test_descriptions_are_not_html
    refute_match Regexp.new("\<b\>this\<\/b\>"), @text,
                 "We had some HTML; icky!"
  end

  # Ensure we get a reasonable amount
  #
  # of space in between paragraphs.
  def test_paragraphs_are_spaced
    assert_match(/amount\n\n\nof space/, @text)
  end

  # @ and {} should be at-sign-prefixed
  def test_escaping
    assert_match(/@@ and @\{@\} should be at-sign-prefixed/)
  end

  # This tests that *bold* and <b>bold me</b> become @strong{bolded}
  def test_bold
    # Seems like a limitation of the Info format: @strong{bold}
    # becomes *bold* when read in Info or M-x info. highly lame!
    assert_match(/@strong\{bold\}/)
    assert_match(/@strong\{bold me\}/)
  end

  # Test that _italics_ and <em>italicize me</em> becomes @emph{italicized}
  def test_italics
    assert_match(/@emph\{italics\}/)
    assert_match(/@emph\{italicize me\}/)
  end

  # And that typewriter +text+ and <tt>typewriter me</tt> becomes @code{typewriter}
  def test_tt
    assert_match(/@code\{text\}/)
    assert_match(/@code\{typewriter me\}/)
  end

  # Check that
  #   anything indented is
  #   verbatim @verb{|foo bar baz|}
  def test_literal_code
    assert_match("@verb{|  anything indented is
  verbatim @@verb@{|foo bar baz|@}
|}")
  end

  # = Huge heading should be a @majorheading
  # == There is also @chapheading
  # === Everything deeper becomes a regular @heading
  # ====== Regardless of its nesting level
  def test_headings
    assert_match(/@majorheading Huge heading should be a @@majorheading/)
    assert_match(/@chapheading There is also @@chapheading/)
    assert_match(/@heading Everything deeper becomes a regular @@heading/)
    assert_match(/@heading Regardless of its nesting level/)
  end

  # * list item
  # * list item2
  #
  # with a paragraph in between
  #
  # - hyphen lists
  # - are also allowed
  #   and items may flow over lines
  def test_bullet_lists
    assert_match("@itemize @bullet
@item
list item
@item
list item2
@end itemize")
    assert_match("@itemize @bullet
@item
hyphen lists
@item
are also allowed and items may flow over lines
@end itemize")
  end

  # 2. numbered lists
  # 8. are made by
  # 9. a digit followed by a period
  def test_numbered_lists
  end

  # a. alpha lists
  # b. should be parsed too
  def test_alpha_lists
  end

  # [cat]   small domestic animal
  # [+cat+] command to copy standard input
  #         to standard output
  def test_labelled_lists
  end

  # * First item.
  #   * Inner item.
  #   * Second inner item.
  # * Second outer item.
  def test_nested_lists
    assert_match("@itemize @bullet
@item
First item.
@itemize @bullet
@item
Inner item.
@item
Second inner item.
@end itemize
@item
Second outer item.
@end itemize")
  end

  def test_internal_hyperlinks
    # be sure to test multi-word hyperlinks as well.
  end

  def test_hyperlink_targets
  end

  def test_web_links
    # An example of the two-argument form: The official
    # @uref{ftp://ftp.gnu.org/gnu, GNU ftp site} holds programs and texts.

    # produces:
    #      The official GNU ftp site (ftp://ftp.gnu.org/gnu)
    #      holds programs and texts.
    # and the HTML output is this:
    #      The official <a href="ftp://ftp.gnu.org/gnu">GNU ftp site</a>
    #      holds programs and texts.
  end

  # three or more hyphens
  # ----
  # should produce a horizontal rule
  def test_horizontal_rule
    # gah; not sure texinfo supports horizontal rules
  end

  private

  # We don't want the whole string inspected if we pass our own
  # message in.
  def assert_match(regex, string = @text,
                   message = "Didn't find #{regex.inspect} in #{string}.")
    assert string[regex] #, message
  end
end

MiniTest::Unit.autorun
