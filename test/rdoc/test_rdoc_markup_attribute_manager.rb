# frozen_string_literal: true
require_relative 'helper'

class TestRDocMarkupAttributeManager < RDoc::TestCase

  def setup
    super

    @am = RDoc::Markup::AttributeManager.new

    @bold_on  = @am.changed_attribute_by_name([], [:BOLD])
    @bold_off = @am.changed_attribute_by_name([:BOLD], [])

    @tt_on    = @am.changed_attribute_by_name([], [:TT])
    @tt_off   = @am.changed_attribute_by_name([:TT], [])

    @em_on    = @am.changed_attribute_by_name([], [:EM])
    @em_off   = @am.changed_attribute_by_name([:EM], [])

    @bold_em_on   = @am.changed_attribute_by_name([], [:BOLD] | [:EM])
    @bold_em_off  = @am.changed_attribute_by_name([:BOLD] | [:EM], [])

    @em_then_bold = @am.changed_attribute_by_name([:EM], [:EM] | [:BOLD])

    @em_to_bold   = @am.changed_attribute_by_name([:EM], [:BOLD])

    @am.add_word_pair("{", "}", :WOMBAT)
    @wombat_on    = @am.changed_attribute_by_name([], [:WOMBAT])
    @wombat_off   = @am.changed_attribute_by_name([:WOMBAT], [])

    @klass = RDoc::Markup::AttributeManager
    @formatter = RDoc::Markup::Formatter.new @rdoc.options
    @formatter.add_tag :BOLD, '<B>', '</B>'
    @formatter.add_tag :EM, '<EM>', '</EM>'
    @formatter.add_tag :TT, '<CODE>', '</CODE>'
  end

  def crossref(text)
    crossref_bitmap = @am.attributes.bitmap_for(:_REGEXP_HANDLING_) |
                      @am.attributes.bitmap_for(:CROSSREF)

    [ @am.changed_attribute_by_name([], [:CROSSREF, :_REGEXP_HANDLING_]),
      RDoc::Markup::RegexpHandling.new(crossref_bitmap, text),
      @am.changed_attribute_by_name([:CROSSREF, :_REGEXP_HANDLING_], [])
    ]
  end

  def test_adding
    assert_equal(["cat ", @wombat_on, "and", @wombat_off, " dog" ],
                  @am.flow("cat {and} dog"))
    #assert_equal(["cat {and} dog" ], @am.flow("cat \\{and} dog"))
  end

  def test_add_html_tag
    @am.add_html("Test", :TEST)
    tags = @am.html_tags
    assert_equal(6, tags.size)
    assert(tags.has_key?("test"))
  end

  def test_add_regexp_handling
    @am.add_regexp_handling "WikiWord", :WIKIWORD
    regexp_handlings = @am.regexp_handlings

    assert_equal 1, regexp_handlings.size
    assert regexp_handlings.assoc "WikiWord"
  end

  def test_add_word_pair
    @am.add_word_pair '%', '&', 'percent and'

    assert @am.word_pair_map.include?(/(%)(\S+)(&)/)
    assert @am.protectable.include?('%')
    assert !@am.protectable.include?('&')
  end

  def test_add_word_pair_angle
    e = assert_raise ArgumentError do
      @am.add_word_pair '<', '>', 'angles'
    end

    assert_equal "Word flags may not start with '<'", e.message
  end

  def test_add_word_pair_invalid
    assert_raise ArgumentError do
      @am.add_word_pair("<", "<", :TEST)
    end
  end

  def test_add_word_pair_map
    @am.add_word_pair("x", "y", :TEST)

    word_pair_map = @am.word_pair_map

    assert_includes word_pair_map.keys.map { |r| r.source }, "(x)(\\S+)(y)"
  end

  def test_add_word_pair_matching
    @am.add_word_pair '^', '^', 'caret'

    assert @am.matching_word_pairs.include?('^')
    assert @am.protectable.include?('^')
  end

  def test_basic
    assert_equal(["cat"], @am.flow("cat"))

    assert_equal(["cat ", @bold_on, "and", @bold_off, " dog"],
                  @am.flow("cat *and* dog"))

    assert_equal(["cat ", @bold_on, "AND", @bold_off, " dog"],
                  @am.flow("cat *AND* dog"))

    assert_equal(["cat ", @em_on, "And", @em_off, " dog"],
                  @am.flow("cat _And_ dog"))

    assert_equal(["cat *and dog*"], @am.flow("cat *and dog*"))

    assert_equal(["*cat and* dog"], @am.flow("*cat and* dog"))

    assert_equal(["cat *and ", @bold_on, "dog", @bold_off],
                  @am.flow("cat *and *dog*"))

    assert_equal(["cat ", @em_on, "and", @em_off, " dog"],
                  @am.flow("cat _and_ dog"))

    assert_equal(["cat_and_dog"],
                  @am.flow("cat_and_dog"))

    assert_equal(["cat ", @tt_on, "and", @tt_off, " dog"],
                  @am.flow("cat +and+ dog"))

    assert_equal(["cat ", @tt_on, "X::Y", @tt_off, " dog"],
                  @am.flow("cat +X::Y+ dog"))

    assert_equal(["cat ", @bold_on, "a_b_c", @bold_off, " dog"],
                  @am.flow("cat *a_b_c* dog"))

    assert_equal(["cat __ dog"],
                  @am.flow("cat __ dog"))

    assert_equal(["cat ", @em_on, "_", @em_off, " dog"],
                  @am.flow("cat ___ dog"))

    assert_equal(["cat and ", @em_on, "5", @em_off, " dogs"],
                  @am.flow("cat and _5_ dogs"))
  end

  def test_bold
    assert_equal [@bold_on, 'bold', @bold_off],
                 @am.flow("*bold*")

    assert_equal [@bold_on, 'Bold:', @bold_off],
                 @am.flow("*Bold:*")

    assert_equal [@bold_on, '\\bold', @bold_off],
                 @am.flow("*\\bold*")
  end

  def test_bold_html_escaped
    assert_equal ['cat <b>dog</b>'], @am.flow('cat \<b>dog</b>')
  end

  def test_combined
    assert_equal(["cat ", @em_on, "and", @em_off, " ", @bold_on, "dog", @bold_off],
                  @am.flow("cat _and_ *dog*"))

    assert_equal(["cat ", @em_on, "a__nd", @em_off, " ", @bold_on, "dog", @bold_off],
                  @am.flow("cat _a__nd_ *dog*"))
  end

  def test_convert_attrs
    str = '+foo+'.dup
    attrs = RDoc::Markup::AttrSpan.new str.length, @am.exclusive_bitmap

    @am.convert_attrs str, attrs, true
    @am.convert_attrs str, attrs

    assert_equal "\000foo\000", str

    str = '+:foo:+'.dup
    attrs = RDoc::Markup::AttrSpan.new str.length, @am.exclusive_bitmap

    @am.convert_attrs str, attrs, true
    @am.convert_attrs str, attrs

    assert_equal "\000:foo:\000", str

    str = '+x-y+'.dup
    attrs = RDoc::Markup::AttrSpan.new str.length, @am.exclusive_bitmap

    @am.convert_attrs str, attrs, true
    @am.convert_attrs str, attrs

    assert_equal "\000x-y\000", str
  end

  def test_convert_attrs_ignores_code
    assert_equal 'foo <CODE>__send__</CODE> bar', output('foo <code>__send__</code> bar')
  end

  def test_convert_attrs_ignores_tt
    assert_equal 'foo <CODE>__send__</CODE> bar', output('foo <tt>__send__</tt> bar')
  end

  def test_convert_attrs_preserves_double
    assert_equal 'foo.__send__ :bar', output('foo.__send__ :bar')
    assert_equal 'use __FILE__ to', output('use __FILE__ to')
  end

  def test_convert_attrs_does_not_ignore_after_tt
    assert_equal 'the <CODE>IF:</CODE><EM>key</EM> directive', output('the <tt>IF:</tt>_key_ directive')
  end

  def test_escapes
    assert_equal '<CODE>text</CODE>',   output('<tt>text</tt>')
    assert_equal '<tt>text</tt>',       output('\\<tt>text</tt>')
    assert_equal '<tt>',                output('\\<tt>')
    assert_equal '<CODE><tt></CODE>',   output('<tt>\\<tt></tt>')
    assert_equal '<CODE>\\<tt></CODE>', output('<tt>\\\\<tt></tt>')
    assert_equal '<B>text</B>',         output('*text*')
    assert_equal '*text*',              output('\\*text*')
    assert_equal '\\',                  output('\\')
    assert_equal '\\text',              output('\\text')
    assert_equal '\\\\text',            output('\\\\text')
    assert_equal 'text \\ text',        output('text \\ text')

    assert_equal 'and <CODE>\\s</CODE> matches space',
                 output('and <tt>\\s</tt> matches space')
    assert_equal 'use <CODE><tt>text</CODE></tt> for code',
                 output('use <tt>\\<tt>text</tt></tt> for code')
    assert_equal 'use <CODE><tt>text</tt></CODE> for code',
                 output('use <tt>\\<tt>text\\</tt></tt> for code')
    assert_equal 'use <tt><tt>text</tt></tt> for code',
                 output('use \\<tt>\\<tt>text</tt></tt> for code')
    assert_equal 'use <tt><CODE>text</CODE></tt> for code',
                 output('use \\<tt><tt>text</tt></tt> for code')
    assert_equal 'use <CODE>+text+</CODE> for code',
                 output('use <tt>\\+text+</tt> for code')
    assert_equal 'use <tt><CODE>text</CODE></tt> for code',
                 output('use \\<tt>+text+</tt> for code')
    assert_equal 'illegal <tag>not</tag> changed',
                 output('illegal <tag>not</tag> changed')
    assert_equal 'unhandled <p>tag</p> unchanged',
                 output('unhandled <p>tag</p> unchanged')
  end

  def test_exclude_tag
    assert_equal '<CODE>aaa</CODE>[:symbol]', output('+aaa+[:symbol]')
    assert_equal '<CODE>aaa[:symbol]</CODE>', output('+aaa[:symbol]+')
    assert_equal 'aaa[:symbol]', output('aaa[:symbol]')
    assert_equal '<B><CODE>index</CODE></B>', output('<b><tt>index</tt></b>')
  end

  def test_exclude_tag_flow
    assert_equal [@tt_on, "aaa", @tt_off, "[:symbol]"],
                  @am.flow("+aaa+[:symbol]")
    assert_equal [@tt_on, "aaa[:symbol]", @tt_off],
                  @am.flow("+aaa[:symbol]+")
    assert_equal ["aaa[:symbol]"],
                  @am.flow("aaa[:symbol]")
  end

  def test_html_like_em_bold
    assert_equal ["cat ", @em_on, "and ", @em_to_bold, "dog", @bold_off],
                  @am.flow("cat <i>and </i><b>dog</b>")
  end

  def test_html_like_em_bold_SGML
    assert_equal ["cat ", @em_on, "and ", @em_to_bold, "dog", @bold_off],
                  @am.flow("cat <i>and <b></i>dog</b>")
  end

  def test_html_like_em_bold_nested_1
    assert_equal(["cat ", @bold_em_on, "and", @bold_em_off, " dog"],
                  @am.flow("cat <i><b>and</b></i> dog"))
  end

  def test_html_like_em_bold_nested_2
    assert_equal ["cat ", @em_on, "and ", @em_then_bold, "dog", @bold_em_off],
                  @am.flow("cat <i>and <b>dog</b></i>")
  end

  def test_html_like_em_bold_nested_mixed_case
    assert_equal ["cat ", @em_on, "and ", @em_then_bold, "dog", @bold_em_off],
                  @am.flow("cat <i>and <B>dog</B></I>")
  end

  def test_html_like_em_bold_mixed_case
    assert_equal ["cat ", @em_on, "and", @em_off, " ", @bold_on, "dog", @bold_off],
                  @am.flow("cat <i>and</i> <B>dog</b>")
  end

  def test_html_like_teletype
    assert_equal ["cat ", @tt_on, "dog", @tt_off],
                 @am.flow("cat <tt>dog</Tt>")
  end

  def test_html_like_teletype_em_bold_SGML
    assert_equal [@tt_on, "cat", @tt_off, " ", @em_on, "and ", @em_to_bold, "dog", @bold_off],
                  @am.flow("<tt>cat</tt> <i>and <b></i>dog</b>")
  end

  def test_initial_html
    html_tags = @am.html_tags
    assert html_tags.is_a?(Hash)
    assert_equal(5, html_tags.size)
  end

  def test_initial_word_pairs
    word_pairs = @am.matching_word_pairs
    assert word_pairs.is_a?(Hash)
    assert_equal(3, word_pairs.size)
  end

  def test_mask_protected_sequence
    def @am.str()     @str       end
    def @am.str=(str) @str = str end

    @am.str = '<code>foo</code>'.dup
    @am.mask_protected_sequences

    assert_equal "<code>foo</code>",       @am.str

    @am.str = '<code>foo\\</code>'.dup
    @am.mask_protected_sequences

    assert_equal "<code>foo<\x04/code>", @am.str, 'escaped close'

    @am.str = '<code>foo\\\\</code>'.dup
    @am.mask_protected_sequences

    assert_equal "<code>foo\\</code>",     @am.str, 'escaped backslash'
  end

  def test_protect
    assert_equal(['cat \\ dog'],
                 @am.flow('cat \\ dog'))

    assert_equal(["cat <tt>dog</Tt>"],
                 @am.flow("cat \\<tt>dog</Tt>"))

    assert_equal(["cat ", @em_on, "and", @em_off, " <B>dog</b>"],
                  @am.flow("cat <i>and</i> \\<B>dog</b>"))

    assert_equal(["*word* or <b>text</b>"],
                 @am.flow("\\*word* or \\<b>text</b>"))

    assert_equal(["_cat_", @em_on, "dog", @em_off],
                  @am.flow("\\_cat_<i>dog</i>"))
  end

  def test_lost_tag_for_the_second_time
    str = "cat <tt>dog</tt>"
    assert_equal(["cat ", @tt_on, "dog", @tt_off],
                 @am.flow(str))
    assert_equal(["cat ", @tt_on, "dog", @tt_off],
                 @am.flow(str))
  end

  def test_regexp_handling
    @am.add_regexp_handling(RDoc::CrossReference::CROSSREF_REGEXP, :CROSSREF)

    #
    # The apostrophes in "cats'" and "dogs'" suppress the flagging of these
    # words as potential cross-references, which is necessary for the unit
    # tests.  Unfortunately, the markup engine right now does not actually
    # check whether a cross-reference is valid before flagging it.
    #
    assert_equal(["cats'"], @am.flow("cats'"))

    assert_equal(["cats' ", crossref("#fred"), " dogs'"].flatten,
                  @am.flow("cats' #fred dogs'"))

    assert_equal([crossref("#fred"), " dogs'"].flatten,
                  @am.flow("#fred dogs'"))

    assert_equal(["cats' ", crossref("#fred")].flatten, @am.flow("cats' #fred"))

    assert_equal(["(", crossref("#fred"), ")"].flatten, @am.flow("(#fred)"))
  end

  def test_tt_html
    assert_equal [@tt_on, '"\n"', @tt_off],
                 @am.flow('<tt>"\n"</tt>')
  end

  def output str
    @formatter.convert_flow @am.flow str
  end

end

