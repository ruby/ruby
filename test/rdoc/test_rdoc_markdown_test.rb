# frozen_string_literal: true
require_relative 'helper'
require 'pp'

require_relative '../../lib/rdoc'
require_relative '../../lib/rdoc/markdown'

class TestRDocMarkdownTest < RDoc::TestCase

  MARKDOWN_TEST_PATH = File.expand_path '../MarkdownTest_1.0.3/', __FILE__

  def setup
    super

    @parser = RDoc::Markdown.new
  end

  def test_amps_and_angle_encoding
    input = File.read "#{MARKDOWN_TEST_PATH}/Amps and angle encoding.text"

    doc = @parser.parse input

    expected =
      doc(
        para("AT&T has an ampersand in their name."),
        para("AT&T is another way to write it."),
        para("This & that."),
        para("4 < 5."),
        para("6 > 5."),
        para("Here's a {link}[http://example.com/?foo=1&bar=2] with " +
             "an ampersand in the URL."),
        para("Here's a link with an amersand in the link text: " +
             "{AT&T}[http://att.com/]."),
        para("Here's an inline {link}[/script?foo=1&bar=2]."),
        para("Here's an inline {link}[/script?foo=1&bar=2]."))

    assert_equal expected, doc
  end

  def test_auto_links
    input = File.read "#{MARKDOWN_TEST_PATH}/Auto links.text"

    doc = @parser.parse input

    # TODO verify rdoc auto-links too
    expected =
      doc(
        para("Link: http://example.com/."),
        para("With an ampersand: http://example.com/?foo=1&bar=2"),
        list(:BULLET,
          item(nil, para("In a list?")),
          item(nil, para("http://example.com/")),
          item(nil, para("It should."))),
        block(
          para("Blockquoted: http://example.com/")),
        para("Auto-links should not occur here: " +
             "<code><http://example.com/></code>"),
        verb("or here: <http://example.com/>\n"))

    assert_equal expected, doc
  end

  def test_backslash_escapes
    input = File.read "#{MARKDOWN_TEST_PATH}/Backslash escapes.text"

    doc = @parser.parse input

    expected =
      doc(
        para("These should all get escaped:"),

        para("Backslash: \\"),
        para("Backtick: `"),
        para("Asterisk: *"),
        para("Underscore: _"),
        para("Left brace: {"),
        para("Right brace: }"),
        para("Left bracket: ["),
        para("Right bracket: ]"),
        para("Left paren: ("),
        para("Right paren: )"),
        para("Greater-than: >"),
        para("Hash: #"),
        para("Period: ."),
        para("Bang: !"),
        para("Plus: +"),
        para("Minus: -"),

        para("These should not, because they occur within a code block:"),

        verb("Backslash: \\\\\n",
             "\n",
             "Backtick: \\`\n",
             "\n",
             "Asterisk: \\*\n",
             "\n",
             "Underscore: \\_\n",
             "\n",
             "Left brace: \\{\n",
             "\n",
             "Right brace: \\}\n",
             "\n",
             "Left bracket: \\[\n",
             "\n",
             "Right bracket: \\]\n",
             "\n",
             "Left paren: \\(\n",
             "\n",
             "Right paren: \\)\n",
             "\n",
             "Greater-than: \\>\n",
             "\n",
             "Hash: \\#\n",
             "\n",
             "Period: \\.\n",
             "\n",
             "Bang: \\!\n",
             "\n",
             "Plus: \\+\n",
             "\n",
             "Minus: \\-\n"),

        para("Nor should these, which occur in code spans:"),

        para("Backslash: <code>\\\\</code>"),
        para("Backtick: <code>\\`</code>"),
        para("Asterisk: <code>\\*</code>"),
        para("Underscore: <code>\\_</code>"),
        para("Left brace: <code>\\{</code>"),
        para("Right brace: <code>\\}</code>"),
        para("Left bracket: <code>\\[</code>"),
        para("Right bracket: <code>\\]</code>"),
        para("Left paren: <code>\\(</code>"),
        para("Right paren: <code>\\)</code>"),
        para("Greater-than: <code>\\></code>"),
        para("Hash: <code>\\#</code>"),
        para("Period: <code>\\.</code>"),
        para("Bang: <code>\\!</code>"),
        para("Plus: <code>\\+</code>"),
        para("Minus: <code>\\-</code>"),

        para("These should get escaped, even though they're matching pairs for\n" +
             "other Markdown constructs:"),

        para("\*asterisks\*"),
        para("\_underscores\_"),
        para("`backticks`"),

        para("This is a code span with a literal backslash-backtick " +
             "sequence: <code>\\`</code>"),

        para("This is a tag with unescaped backticks " +
             "<span attr='`ticks`'>bar</span>."),

        para("This is a tag with backslashes " +
             "<span attr='\\\\backslashes\\\\'>bar</span>."))

    assert_equal expected, doc
  end

  def test_blockquotes_with_code_blocks
    input = File.read "#{MARKDOWN_TEST_PATH}/Blockquotes with code blocks.text"

    doc = @parser.parse input

    expected =
      doc(
        block(
          para("Example:"),
          verb("sub status {\n",
               "    print \"working\";\n",
               "}\n"),
          para("Or:"),
          verb("sub status {\n",
               "    return \"working\";\n",
               "}\n")))

    assert_equal expected, doc
  end

  def test_code_blocks
    input = File.read "#{MARKDOWN_TEST_PATH}/Code Blocks.text"

    doc = @parser.parse input

    expected =
      doc(
        verb("code block on the first line\n"),
        para("Regular text."),

        verb("code block indented by spaces\n"),
        para("Regular text."),

        verb("the lines in this block  \n",
             "all contain trailing spaces  \n"),
        para("Regular Text."),

        verb("code block on the last line\n"))

    assert_equal expected, doc
  end

  def test_code_spans
    input = File.read "#{MARKDOWN_TEST_PATH}/Code Spans.text"

    doc = @parser.parse input

    expected = doc(
      para("<code><test a=\"</code> content of attribute <code>\"></code>"),
      para("Fix for backticks within HTML tag: " +
           "<span attr='`ticks`'>like this</span>"),
      para("Here's how you put <code>`backticks`</code> in a code span."))

    assert_equal expected, doc
  end

  def test_hard_wrapped_paragraphs_with_list_like_lines
    input = File.read "#{MARKDOWN_TEST_PATH}/Hard-wrapped paragraphs with list-like lines.text"

    doc = @parser.parse input

    expected =
      doc(
        para("In Markdown 1.0.0 and earlier. Version\n" +
             "8. This line turns into a list item.\n"   +
             "Because a hard-wrapped line in the\n"     +
             "middle of a paragraph looked like a\n"    +
             "list item."),
        para("Here's one with a bullet.\n" +
             "* criminey."))

    assert_equal expected, doc
  end

  def test_horizontal_rules
    input = File.read "#{MARKDOWN_TEST_PATH}/Horizontal rules.text"

    doc = @parser.parse input

    expected =
      doc(
        para("Dashes:"),

        rule(1),
        rule(1),
        rule(1),
        rule(1),
        verb("---\n"),

        rule(1),
        rule(1),
        rule(1),
        rule(1),
        verb("- - -\n"),

        para("Asterisks:"),

        rule(1),
        rule(1),
        rule(1),
        rule(1),
        verb("***\n"),

        rule(1),
        rule(1),
        rule(1),
        rule(1),
        verb("* * *\n"),

        para("Underscores:"),

        rule(1),
        rule(1),
        rule(1),
        rule(1),
        verb("___\n"),

        rule(1),
        rule(1),
        rule(1),
        rule(1),
        verb("_ _ _\n"))

    assert_equal expected, doc
  end

  def test_inline_html_advanced
    input = File.read "#{MARKDOWN_TEST_PATH}/Inline HTML (Advanced).text"

    @parser.html = true

    doc = @parser.parse input

    expected =
      doc(
        para("Simple block on one line:"),
        raw("<div>foo</div>"),
        para("And nested without indentation:"),
        raw(<<-RAW.chomp))
<div>
<div>
<div>
foo
</div>
<div style=">"/>
</div>
<div>bar</div>
</div>
        RAW

    assert_equal expected, doc
  end

  def test_inline_html_simple
    input = File.read "#{MARKDOWN_TEST_PATH}/Inline HTML (Simple).text"

    @parser.html = true

    doc = @parser.parse input

    expected =
      doc(
       para("Here's a simple block:"),
       raw("<div>\n\tfoo\n</div>"),

       para("This should be a code block, though:"),
       verb("<div>\n",
            "\tfoo\n",
            "</div>\n"),

       para("As should this:"),
       verb("<div>foo</div>\n"),

       para("Now, nested:"),
       raw("<div>\n\t<div>\n\t\t<div>\n\t\t\tfoo\n" +
           "\t\t</div>\n\t</div>\n</div>"),

       para("This should just be an HTML comment:"),
       raw("<!-- Comment -->"),

       para("Multiline:"),
       raw("<!--\nBlah\nBlah\n-->"),

       para("Code block:"),
       verb("<!-- Comment -->\n"),

       para("Just plain comment, with trailing spaces on the line:"),
       raw("<!-- foo -->"),

       para("Code:"),
       verb("<hr />\n"),

       para("Hr's:"),
       raw("<hr>"),
       raw("<hr/>"),
       raw("<hr />"),

       raw("<hr>"),
       raw("<hr/>"),
       raw("<hr />"),

       raw("<hr class=\"foo\" id=\"bar\" />"),
       raw("<hr class=\"foo\" id=\"bar\"/>"),
       raw("<hr class=\"foo\" id=\"bar\" >"))

    assert_equal expected, doc
  end

  def test_inline_html_comments
    input = File.read "#{MARKDOWN_TEST_PATH}/Inline HTML comments.text"

    doc = @parser.parse input

    expected =
      doc(
        para("Paragraph one."),

        raw("<!-- This is a simple comment -->"),

        raw("<!--\n\tThis is another comment.\n-->"),

        para("Paragraph two."),

        raw("<!-- one comment block -- -- with two comments -->"),

        para("The end."))

    assert_equal expected, doc
  end

  def test_links_inline_style
    input = File.read "#{MARKDOWN_TEST_PATH}/Links, inline style.text"

    doc = @parser.parse input

    expected =
      doc(
        para("Just a {URL}[/url/]."),
        para("{URL and title}[/url/]."),
        para("{URL and title}[/url/]."),
        para("{URL and title}[/url/]."),
        para("{URL and title}[/url/]."),
        para("{Empty}[]."))

    assert_equal expected, doc
  end

  def test_links_reference_style
    input = File.read "#{MARKDOWN_TEST_PATH}/Links, reference style.text"

    doc = @parser.parse input

    expected =
      doc(
        para("Foo {bar}[/url/]."),
        para("Foo {bar}[/url/]."),
        para("Foo {bar}[/url/]."),

        para("With {embedded [brackets]}[/url/]."),

        para("Indented {once}[/url]."),
        para("Indented {twice}[/url]."),
        para("Indented {thrice}[/url]."),
        para("Indented [four][] times."),

        verb("[four]: /url\n"),

        rule(1),

        para("{this}[foo] should work"),
        para("So should {this}[foo]."),
        para("And {this}[foo]."),
        para("And {this}[foo]."),
        para("And {this}[foo]."),

        para("But not [that] []."),
        para("Nor [that][]."),
        para("Nor [that]."),

        para("[Something in brackets like {this}[foo] should work]"),
        para("[Same with {this}[foo].]"),

        para("In this case, {this}[/somethingelse/] points to something else."),
        para("Backslashing should suppress [this] and [this]."),

        rule(1),

        para("Here's one where the {link breaks}[/url/] across lines."),
        para("Here's another where the {link breaks}[/url/] across lines, " +
             "but with a line-ending space."))

    assert_equal expected, doc
  end

  def test_links_shortcut_references
    input = File.read "#{MARKDOWN_TEST_PATH}/Links, shortcut references.text"

    doc = @parser.parse input

    expected =
      doc(
        para("This is the {simple case}[/simple]."),
        para("This one has a {line break}[/foo]."),
        para("This one has a {line break}[/foo] with a line-ending space."),
        para("{this}[/that] and the {other}[/other]"))

    assert_equal expected, doc
  end

  def test_literal_quotes_in_titles
    input = File.read "#{MARKDOWN_TEST_PATH}/Literal quotes in titles.text"

    doc = @parser.parse input

    # TODO support title attribute
    expected =
      doc(
        para("Foo {bar}[/url/]."),
        para("Foo {bar}[/url/]."))

    assert_equal expected, doc
  end

  def test_markdown_documentation_basics
    input = File.read "#{MARKDOWN_TEST_PATH}/Markdown Documentation - Basics.text"

    doc = @parser.parse input

    expected =
      doc(
        head(1, "Markdown: Basics"),

        raw(<<-RAW.chomp),
<ul id="ProjectSubmenu">
    <li><a href="/projects/markdown/" title="Markdown Project Page">Main</a></li>
    <li><a class="selected" title="Markdown Basics">Basics</a></li>
    <li><a href="/projects/markdown/syntax" title="Markdown Syntax Documentation">Syntax</a></li>
    <li><a href="/projects/markdown/license" title="Pricing and License Information">License</a></li>
    <li><a href="/projects/markdown/dingus" title="Online Markdown Web Form">Dingus</a></li>
</ul>
        RAW

        head(2, "Getting the Gist of Markdown's Formatting Syntax"),

        para("This page offers a brief overview of what it's like to use Markdown.\n" +
             "The {syntax page}[/projects/markdown/syntax] provides complete, detailed documentation for\n" +
             "every feature, but Markdown should be very easy to pick up simply by\n" +
             "looking at a few examples of it in action. The examples on this page\n" +
             "are written in a before/after style, showing example syntax and the\n" +
             "HTML output produced by Markdown."),

        para("It's also helpful to simply try Markdown out; the {Dingus}[/projects/markdown/dingus] is a\n" +
             "web application that allows you type your own Markdown-formatted text\n" +
             "and translate it to XHTML."),

        para("<b>Note:</b> This document is itself written using Markdown; you\n" +
             "can {see the source for it by adding '.text' to the URL}[/projects/markdown/basics.text]."),

        head(2, "Paragraphs, Headers, Blockquotes"),

        para("A paragraph is simply one or more consecutive lines of text, separated\n" +
             "by one or more blank lines. (A blank line is any line that looks like a\n" +
             "blank line -- a line containing nothing spaces or tabs is considered\n" +
             "blank.) Normal paragraphs should not be intended with spaces or tabs."),

        para("Markdown offers two styles of headers: _Setext_ and _atx_.\n" +
             "Setext-style headers for <code><h1></code> and <code><h2></code> are created by\n" +
             "\"underlining\" with equal signs (<code>=</code>) and hyphens (<code>-</code>), respectively.\n" +
             "To create an atx-style header, you put 1-6 hash marks (<code>#</code>) at the\n" +
             "beginning of the line -- the number of hashes equals the resulting\n" +
             "HTML header level."),

        para("Blockquotes are indicated using email-style '<code>></code>' angle brackets."),

        para("Markdown:"),

        verb("A First Level Header\n",
             "====================\n",
             "\n",
             "A Second Level Header\n",
             "---------------------\n",
             "\n",
             "Now is the time for all good men to come to\n",
             "the aid of their country. This is just a\n",
             "regular paragraph.\n",
             "\n",
             "The quick brown fox jumped over the lazy\n",
             "dog's back.\n",
             "\n",
             "### Header 3\n",
             "\n",
             "> This is a blockquote.\n",
             "> \n",
             "> This is the second paragraph in the blockquote.\n",
             ">\n",
             "> ## This is an H2 in a blockquote\n"),

        para("Output:"),

        verb("<h1>A First Level Header</h1>\n",
             "\n",
             "<h2>A Second Level Header</h2>\n",
             "\n",
             "<p>Now is the time for all good men to come to\n",
             "the aid of their country. This is just a\n",
             "regular paragraph.</p>\n",
             "\n",
             "<p>The quick brown fox jumped over the lazy\n",
             "dog's back.</p>\n",
             "\n",
             "<h3>Header 3</h3>\n",
             "\n",
             "<blockquote>\n",
             "    <p>This is a blockquote.</p>\n",
             "\n",
             "    <p>This is the second paragraph in the blockquote.</p>\n",
             "\n",
             "    <h2>This is an H2 in a blockquote</h2>\n",
             "</blockquote>\n"),

        head(3, "Phrase Emphasis"),
        para("Markdown uses asterisks and underscores to indicate spans of emphasis."),

        para("Markdown:"),

        verb("Some of these words *are emphasized*.\n",
             "Some of these words _are emphasized also_.\n",
             "\n",
             "Use two asterisks for **strong emphasis**.\n",
             "Or, if you prefer, __use two underscores instead__.\n"),

        para("Output:"),

        verb("<p>Some of these words <em>are emphasized</em>.\n",
             "Some of these words <em>are emphasized also</em>.</p>\n",
             "\n",
             "<p>Use two asterisks for <strong>strong emphasis</strong>.\n",
             "Or, if you prefer, <strong>use two underscores instead</strong>.</p>\n"),

        head(2, "Lists"),

        para("Unordered (bulleted) lists use asterisks, pluses, and hyphens (<code>*</code>,\n" +
             "<code>+</code>, and <code>-</code>) as list markers. These three markers are\n" +
             "interchangeable; this:"),

        verb("*   Candy.\n",
             "*   Gum.\n",
             "*   Booze.\n"),

        para("this:"),

        verb("+   Candy.\n",
             "+   Gum.\n",
             "+   Booze.\n"),

        para("and this:"),

        verb("-   Candy.\n",
             "-   Gum.\n",
             "-   Booze.\n"),

        para("all produce the same output:"),

        verb("<ul>\n",
             "<li>Candy.</li>\n",
             "<li>Gum.</li>\n",
             "<li>Booze.</li>\n",
             "</ul>\n"),

        para("Ordered (numbered) lists use regular numbers, followed by periods, as\n" +
             "list markers:"),

        verb("1.  Red\n",
             "2.  Green\n",
             "3.  Blue\n"),

        para("Output:"),

        verb("<ol>\n",
             "<li>Red</li>\n",
             "<li>Green</li>\n",
             "<li>Blue</li>\n",
             "</ol>\n"),

        para("If you put blank lines between items, you'll get <code><p></code> tags for the\n" +
             "list item text. You can create multi-paragraph list items by indenting\n" +
             "the paragraphs by 4 spaces or 1 tab:"),

        verb("*   A list item.\n",
             "\n",
             "    With multiple paragraphs.\n",
             "\n",
             "*   Another item in the list.\n"),

        para("Output:"),

        verb("<ul>\n",
             "<li><p>A list item.</p>\n",
             "<p>With multiple paragraphs.</p></li>\n",
             "<li><p>Another item in the list.</p></li>\n",
             "</ul>\n"),

        head(3, "Links"),

        para("Markdown supports two styles for creating links: _inline_ and\n" +
             "_reference_. With both styles, you use square brackets to delimit the\n" +
             "text you want to turn into a link."),

        para("Inline-style links use parentheses immediately after the link text.\n" +
             "For example:"),

        verb("This is an [example link](http://example.com/).\n"),

        para("Output:"),

        verb("<p>This is an <a href=\"http://example.com/\">\n",
             "example link</a>.</p>\n"),

        para("Optionally, you may include a title attribute in the parentheses:"),

        verb("This is an [example link](http://example.com/ \"With a Title\").\n"),

        para("Output:"),

        verb("<p>This is an <a href=\"http://example.com/\" title=\"With a Title\">\n",
             "example link</a>.</p>\n"),

        para("Reference-style links allow you to refer to your links by names, which\n" +
             "you define elsewhere in your document:"),

        verb("I get 10 times more traffic from [Google][1] than from\n",
             "[Yahoo][2] or [MSN][3].\n",
             "\n",
             "[1]: http://google.com/        \"Google\"\n",
             "[2]: http://search.yahoo.com/  \"Yahoo Search\"\n",
             "[3]: http://search.msn.com/    \"MSN Search\"\n"),

        para("Output:"),

        verb("<p>I get 10 times more traffic from <a href=\"http://google.com/\"\n",
             "title=\"Google\">Google</a> than from <a href=\"http://search.yahoo.com/\"\n",
             "title=\"Yahoo Search\">Yahoo</a> or <a href=\"http://search.msn.com/\"\n",
             "title=\"MSN Search\">MSN</a>.</p>\n"),

        para("The title attribute is optional. Link names may contain letters,\n" +
             "numbers and spaces, but are _not_ case sensitive:"),

        verb("I start my morning with a cup of coffee and\n",
             "[The New York Times][NY Times].\n",
             "\n",
             "[ny times]: http://www.nytimes.com/\n"),

        para("Output:"),

        verb("<p>I start my morning with a cup of coffee and\n",
             "<a href=\"http://www.nytimes.com/\">The New York Times</a>.</p>\n"),

        head(3, "Images"),

        para("Image syntax is very much like link syntax."),

        para("Inline (titles are optional):"),

        verb("![alt text](/path/to/img.jpg \"Title\")\n"),

        para("Reference-style:"),

        verb("![alt text][id]\n",
             "\n",
             "[id]: /path/to/img.jpg \"Title\"\n"),

        para("Both of the above examples produce the same output:"),

        verb("<img src=\"/path/to/img.jpg\" alt=\"alt text\" title=\"Title\" />\n"),

        head(3, "Code"),

        para("In a regular paragraph, you can create code span by wrapping text in\n" +
             "backtick quotes. Any ampersands (<code>&</code>) and angle brackets (<code><</code> or\n" +
             "<code>></code>) will automatically be translated into HTML entities. This makes\n" +
             "it easy to use Markdown to write about HTML example code:"),

        verb(
             "I strongly recommend against using any `<blink>` tags.\n",
             "\n",
             "I wish SmartyPants used named entities like `&mdash;`\n",
             "instead of decimal-encoded entities like `&#8212;`.\n"),

        para("Output:"),

        verb("<p>I strongly recommend against using any\n",
             "<code>&lt;blink&gt;</code> tags.</p>\n",
             "\n",
             "<p>I wish SmartyPants used named entities like\n",
             "<code>&amp;mdash;</code> instead of decimal-encoded\n",
             "entities like <code>&amp;#8212;</code>.</p>\n"),

        para("To specify an entire block of pre-formatted code, indent every line of\n" +
             "the block by 4 spaces or 1 tab. Just like with code spans, <code>&</code>, <code><</code>,\n" +
             "and <code>></code> characters will be escaped automatically."),

        para("Markdown:"),

        verb("If you want your page to validate under XHTML 1.0 Strict,\n",
             "you've got to put paragraph tags in your blockquotes:\n",
             "\n",
             "    <blockquote>\n",
             "        <p>For example.</p>\n",
             "    </blockquote>\n"),

        para("Output:"),

        verb("<p>If you want your page to validate under XHTML 1.0 Strict,\n",
             "you've got to put paragraph tags in your blockquotes:</p>\n",
             "\n",
             "<pre><code>&lt;blockquote&gt;\n",
             "    &lt;p&gt;For example.&lt;/p&gt;\n",
             "&lt;/blockquote&gt;\n",
             "</code></pre>\n"))

    assert_equal expected, doc
  end

  def test_markdown_documentation_syntax
    input = File.read "#{MARKDOWN_TEST_PATH}/Markdown Documentation - Syntax.text"

    doc = @parser.parse input

    expected =
      doc(
        head(1, "Markdown: Syntax"),

        raw(<<-RAW.chomp),
<ul id="ProjectSubmenu">
    <li><a href="/projects/markdown/" title="Markdown Project Page">Main</a></li>
    <li><a href="/projects/markdown/basics" title="Markdown Basics">Basics</a></li>
    <li><a class="selected" title="Markdown Syntax Documentation">Syntax</a></li>
    <li><a href="/projects/markdown/license" title="Pricing and License Information">License</a></li>
    <li><a href="/projects/markdown/dingus" title="Online Markdown Web Form">Dingus</a></li>
</ul>
        RAW

        list(:BULLET,
          item(nil,
            para("{Overview}[#overview]"),
            list(:BULLET,
              item(nil,
                para("{Philosophy}[#philosophy]")),
              item(nil,
                para("{Inline HTML}[#html]")),
              item(nil,
                para("{Automatic Escaping for Special Characters}[#autoescape]")))),
          item(nil,
            para("{Block Elements}[#block]"),
            list(:BULLET,
              item(nil,
                para("{Paragraphs and Line Breaks}[#p]")),
              item(nil,
                para("{Headers}[#header]")),
              item(nil,
                para("{Blockquotes}[#blockquote]")),
              item(nil,
                para("{Lists}[#list]")),
              item(nil,
                para("{Code Blocks}[#precode]")),
              item(nil,
                para("{Horizontal Rules}[#hr]")))),
          item(nil,
            para("{Span Elements}[#span]"),
            list(:BULLET,
              item(nil,
                para("{Links}[#link]")),
              item(nil,
                para("{Emphasis}[#em]")),
              item(nil,
                para("{Code}[#code]")),
              item(nil,
                para("{Images}[#img]")))),
          item(nil,
            para("{Miscellaneous}[#misc]"),
            list(:BULLET,
              item(nil,
                para("{Backslash Escapes}[#backslash]")),
              item(nil,
                para("{Automatic Links}[#autolink]"))))),

        para("<b>Note:</b> This document is itself written using Markdown; you\n" +
             "can {see the source for it by adding '.text' to the URL}[/projects/markdown/syntax.text]."),

        rule(1),

        raw("<h2 id=\"overview\">Overview</h2>"),

        raw("<h3 id=\"philosophy\">Philosophy</h3>"),

        para("Markdown is intended to be as easy-to-read and easy-to-write as is feasible."),

        para("Readability, however, is emphasized above all else. A Markdown-formatted\n" +
             "document should be publishable as-is, as plain text, without looking\n" +
             "like it's been marked up with tags or formatting instructions. While\n" +
             "Markdown's syntax has been influenced by several existing text-to-HTML\n" +
             "filters -- including {Setext}[http://docutils.sourceforge.net/mirror/setext.html], {atx}[http://www.aaronsw.com/2002/atx/], {Textile}[http://textism.com/tools/textile/], {reStructuredText}[http://docutils.sourceforge.net/rst.html],\n" +
             "{Grutatext}[http://www.triptico.com/software/grutatxt.html], and {EtText}[http://ettext.taint.org/doc/] -- the single biggest source of\n" +
             "inspiration for Markdown's syntax is the format of plain text email."),

        para("To this end, Markdown's syntax is comprised entirely of punctuation\n" +
             "characters, which punctuation characters have been carefully chosen so\n" +
             "as to look like what they mean. E.g., asterisks around a word actually\n" +
             "look like \*emphasis\*. Markdown lists look like, well, lists. Even\n" +
             "blockquotes look like quoted passages of text, assuming you've ever\n" +
             "used email."),

        raw("<h3 id=\"html\">Inline HTML</h3>"),

        para("Markdown's syntax is intended for one purpose: to be used as a\n" +
             "format for _writing_ for the web."),

        para("Markdown is not a replacement for HTML, or even close to it. Its\n" +
             "syntax is very small, corresponding only to a very small subset of\n" +
             "HTML tags. The idea is _not_ to create a syntax that makes it easier\n" +
             "to insert HTML tags. In my opinion, HTML tags are already easy to\n" +
             "insert. The idea for Markdown is to make it easy to read, write, and\n" +
             "edit prose. HTML is a _publishing_ format; Markdown is a _writing_\n" +
             "format. Thus, Markdown's formatting syntax only addresses issues that\n" +
             "can be conveyed in plain text."),

        para("For any markup that is not covered by Markdown's syntax, you simply\n" +
             "use HTML itself. There's no need to preface it or delimit it to\n" +
             "indicate that you're switching from Markdown to HTML; you just use\n" +
             "the tags."),

        para("The only restrictions are that block-level HTML elements -- e.g. <code><div></code>,\n" +
             "<code><table></code>, <code><pre></code>, <code><p></code>, etc. -- must be separated from surrounding\n" +
             "content by blank lines, and the start and end tags of the block should\n" +
             "not be indented with tabs or spaces. Markdown is smart enough not\n" +
             "to add extra (unwanted) <code><p></code> tags around HTML block-level tags."),

        para("For example, to add an HTML table to a Markdown article:"),

        verb("This is a regular paragraph.\n",
             "\n",
             "<table>\n",
             "    <tr>\n",
             "        <td>Foo</td>\n",
             "    </tr>\n",
             "</table>\n",
             "\n",
             "This is another regular paragraph.\n"),

        para("Note that Markdown formatting syntax is not processed within block-level\n" +
             "HTML tags. E.g., you can't use Markdown-style <code>*emphasis*</code> inside an\n" +
             "HTML block."),

        para("Span-level HTML tags -- e.g. <code><span></code>, <code><cite></code>, or <code><del></code> -- can be\n" +
             "used anywhere in a Markdown paragraph, list item, or header. If you\n" +
             "want, you can even use HTML tags instead of Markdown formatting; e.g. if\n" +
             "you'd prefer to use HTML <code><a></code> or <code><img></code> tags instead of Markdown's\n" +
             "link or image syntax, go right ahead."),

        para("Unlike block-level HTML tags, Markdown syntax _is_ processed within\n" +
             "span-level tags."),

        raw("<h3 id=\"autoescape\">Automatic Escaping for Special Characters</h3>"),

        para("In HTML, there are two characters that demand special treatment: <code><</code>\n" +
             "and <code>&</code>. Left angle brackets are used to start tags; ampersands are\n" +
             "used to denote HTML entities. If you want to use them as literal\n" +
             "characters, you must escape them as entities, e.g. <code>&lt;</code>, and\n" +
             "<code>&amp;</code>."),

        para("Ampersands in particular are bedeviling for web writers. If you want to\n" +
             "write about 'AT&T', you need to write '<code>AT&amp;T</code>'. You even need to\n" +
             "escape ampersands within URLs. Thus, if you want to link to:"),

        verb("http://images.google.com/images?num=30&q=larry+bird\n"),

        para("you need to encode the URL as:"),

        verb("http://images.google.com/images?num=30&amp;q=larry+bird\n"),

        para("in your anchor tag <code>href</code> attribute. Needless to say, this is easy to\n" +
             "forget, and is probably the single most common source of HTML validation\n" +
             "errors in otherwise well-marked-up web sites."),

        para("Markdown allows you to use these characters naturally, taking care of\n" +
             "all the necessary escaping for you. If you use an ampersand as part of\n" +
             "an HTML entity, it remains unchanged; otherwise it will be translated\n" +
             "into <code>&amp;</code>."),

        para("So, if you want to include a copyright symbol in your article, you can write:"),

        verb("&copy;\n"),

        para("and Markdown will leave it alone. But if you write:"),

        verb("AT&T\n"),

        para("Markdown will translate it to:"),

        verb("AT&amp;T\n"),

        para("Similarly, because Markdown supports {inline HTML}[#html], if you use\n" +
             "angle brackets as delimiters for HTML tags, Markdown will treat them as\n" +
             "such. But if you write:"),

        verb("4 < 5\n"),

        para("Markdown will translate it to:"),

        verb("4 &lt; 5\n"),

        para("However, inside Markdown code spans and blocks, angle brackets and\n" +
             "ampersands are _always_ encoded automatically. This makes it easy to use\n" +
             "Markdown to write about HTML code. (As opposed to raw HTML, which is a\n" +
             "terrible format for writing about HTML syntax, because every single <code><</code>\n" +
             "and <code>&</code> in your example code needs to be escaped.)"),

        rule(1),

        raw("<h2 id=\"block\">Block Elements</h2>"),

        raw("<h3 id=\"p\">Paragraphs and Line Breaks</h3>"),

        para("A paragraph is simply one or more consecutive lines of text, separated\n" +
             "by one or more blank lines. (A blank line is any line that looks like a\n" +
             "blank line -- a line containing nothing but spaces or tabs is considered\n" +
             "blank.) Normal paragraphs should not be intended with spaces or tabs."),

        para("The implication of the \"one or more consecutive lines of text\" rule is\n" +
             "that Markdown supports \"hard-wrapped\" text paragraphs. This differs\n" +
             "significantly from most other text-to-HTML formatters (including Movable\n" +
             "Type's \"Convert Line Breaks\" option) which translate every line break\n" +
             "character in a paragraph into a <code><br /></code> tag."),

        para("When you _do_ want to insert a <code><br /></code> break tag using Markdown, you\n" +
             "end a line with two or more spaces, then type return."),

        para("Yes, this takes a tad more effort to create a <code><br /></code>, but a simplistic\n" +
             "\"every line break is a <code><br /></code>\" rule wouldn't work for Markdown.\n" +
             "Markdown's email-style {blockquoting}[#blockquote] and multi-paragraph {list items}[#list]\n" +
             "work best -- and look better -- when you format them with hard breaks."),

        raw("<h3 id=\"header\">Headers</h3>"),

        para("Markdown supports two styles of headers, {Setext}[http://docutils.sourceforge.net/mirror/setext.html] and {atx}[http://www.aaronsw.com/2002/atx/]."),

        para("Setext-style headers are \"underlined\" using equal signs (for first-level\n" +
             "headers) and dashes (for second-level headers). For example:"),

        verb("This is an H1\n",
             "=============\n",
             "\n",
             "This is an H2\n",
             "-------------\n"),

        para("Any number of underlining <code>=</code>'s or <code>-</code>'s will work."),

        para("Atx-style headers use 1-6 hash characters at the start of the line,\n" +
             "corresponding to header levels 1-6. For example:"),

        verb("# This is an H1\n",
             "\n",
             "## This is an H2\n",
             "\n",
             "###### This is an H6\n"),

        para("Optionally, you may \"close\" atx-style headers. This is purely\n" +
             "cosmetic -- you can use this if you think it looks better. The\n" +
             "closing hashes don't even need to match the number of hashes\n" +
             "used to open the header. (The number of opening hashes\n" +
             "determines the header level.) :"),

        verb("# This is an H1 #\n",
             "\n",
             "## This is an H2 ##\n",
             "\n",
             "### This is an H3 ######\n"),

        raw("<h3 id=\"blockquote\">Blockquotes</h3>"),

        para(
             "Markdown uses email-style <code>></code> characters for blockquoting. If you're\n" +
             "familiar with quoting passages of text in an email message, then you\n" +
             "know how to create a blockquote in Markdown. It looks best if you hard\n" +
             "wrap the text and put a <code>></code> before every line:"),

        verb("> This is a blockquote with two paragraphs. Lorem ipsum dolor sit amet,\n",
             "> consectetuer adipiscing elit. Aliquam hendrerit mi posuere lectus.\n",
             "> Vestibulum enim wisi, viverra nec, fringilla in, laoreet vitae, risus.\n",
             "> \n",
             "> Donec sit amet nisl. Aliquam semper ipsum sit amet velit. Suspendisse\n",
             "> id sem consectetuer libero luctus adipiscing.\n"),

        para("Markdown allows you to be lazy and only put the <code>></code> before the first\n" +
             "line of a hard-wrapped paragraph:"),

        verb("> This is a blockquote with two paragraphs. Lorem ipsum dolor sit amet,\n",
             "consectetuer adipiscing elit. Aliquam hendrerit mi posuere lectus.\n",
             "Vestibulum enim wisi, viverra nec, fringilla in, laoreet vitae, risus.\n",
             "\n",
             "> Donec sit amet nisl. Aliquam semper ipsum sit amet velit. Suspendisse\n",
             "id sem consectetuer libero luctus adipiscing.\n"),

        para("Blockquotes can be nested (i.e. a blockquote-in-a-blockquote) by\n" +
             "adding additional levels of <code>></code>:"),

        verb("> This is the first level of quoting.\n",
             ">\n",
             "> > This is nested blockquote.\n",
             ">\n",
             "> Back to the first level.\n"),

        para("Blockquotes can contain other Markdown elements, including headers, lists,\n" +
             "and code blocks:"),

        verb("> ## This is a header.\n",
             "> \n",
             "> 1.   This is the first list item.\n",
             "> 2.   This is the second list item.\n",
             "> \n",
             "> Here's some example code:\n",
             "> \n",
             ">     return shell_exec(\"echo $input | $markdown_script\");\n"),

        para("Any decent text editor should make email-style quoting easy. For\n" +
             "example, with BBEdit, you can make a selection and choose Increase\n" +
             "Quote Level from the Text menu."),

        raw("<h3 id=\"list\">Lists</h3>"),

        para("Markdown supports ordered (numbered) and unordered (bulleted) lists."),

        para("Unordered lists use asterisks, pluses, and hyphens -- interchangeably\n" +
             "-- as list markers:"),

        verb("*   Red\n",
             "*   Green\n",
             "*   Blue\n"),

        para("is equivalent to:"),

        verb("+   Red\n",
             "+   Green\n",
             "+   Blue\n"),

        para("and:"),

        verb("-   Red\n",
             "-   Green\n",
             "-   Blue\n"),

        para("Ordered lists use numbers followed by periods:"),

        verb("1.  Bird\n",
             "2.  McHale\n",
             "3.  Parish\n"),

        para("It's important to note that the actual numbers you use to mark the\n" +
             "list have no effect on the HTML output Markdown produces. The HTML\n" +
             "Markdown produces from the above list is:"),

        verb("<ol>\n",
             "<li>Bird</li>\n",
             "<li>McHale</li>\n",
             "<li>Parish</li>\n",
             "</ol>\n"),

        para("If you instead wrote the list in Markdown like this:"),

        verb("1.  Bird\n",
             "1.  McHale\n",
             "1.  Parish\n"),

        para("or even:"),

        verb("3. Bird\n",
             "1. McHale\n",
             "8. Parish\n"),

        para("you'd get the exact same HTML output. The point is, if you want to,\n" +
             "you can use ordinal numbers in your ordered Markdown lists, so that\n" +
             "the numbers in your source match the numbers in your published HTML.\n" +
             "But if you want to be lazy, you don't have to."),

        para("If you do use lazy list numbering, however, you should still start the\n" +
             "list with the number 1. At some point in the future, Markdown may support\n" +
             "starting ordered lists at an arbitrary number."),

        para("List markers typically start at the left margin, but may be indented by\n" +
             "up to three spaces. List markers must be followed by one or more spaces\n" +
             "or a tab."),

        para("To make lists look nice, you can wrap items with hanging indents:"),

        verb("*   Lorem ipsum dolor sit amet, consectetuer adipiscing elit.\n",
             "    Aliquam hendrerit mi posuere lectus. Vestibulum enim wisi,\n",
             "    viverra nec, fringilla in, laoreet vitae, risus.\n",
             "*   Donec sit amet nisl. Aliquam semper ipsum sit amet velit.\n",
             "    Suspendisse id sem consectetuer libero luctus adipiscing.\n"),

        para("But if you want to be lazy, you don't have to:"),

        verb("*   Lorem ipsum dolor sit amet, consectetuer adipiscing elit.\n",
             "Aliquam hendrerit mi posuere lectus. Vestibulum enim wisi,\n",
             "viverra nec, fringilla in, laoreet vitae, risus.\n",
             "*   Donec sit amet nisl. Aliquam semper ipsum sit amet velit.\n",
             "Suspendisse id sem consectetuer libero luctus adipiscing.\n"),

        para("If list items are separated by blank lines, Markdown will wrap the\n" +
             "items in <code><p></code> tags in the HTML output. For example, this input:"),

        verb("*   Bird\n",
             "*   Magic\n"),

        para("will turn into:"),

        verb("<ul>\n",
             "<li>Bird</li>\n",
             "<li>Magic</li>\n",
             "</ul>\n"),

        para("But this:"),

        verb("*   Bird\n",
             "\n",
             "*   Magic\n"),

        para("will turn into:"),

        verb("<ul>\n",
             "<li><p>Bird</p></li>\n",
             "<li><p>Magic</p></li>\n",
             "</ul>\n"),

        para("List items may consist of multiple paragraphs. Each subsequent\n" +
             "paragraph in a list item must be intended by either 4 spaces\n" +
             "or one tab:"),

        verb("1.  This is a list item with two paragraphs. Lorem ipsum dolor\n",
             "    sit amet, consectetuer adipiscing elit. Aliquam hendrerit\n",
             "    mi posuere lectus.\n",
             "\n",
             "    Vestibulum enim wisi, viverra nec, fringilla in, laoreet\n",
             "    vitae, risus. Donec sit amet nisl. Aliquam semper ipsum\n",
             "    sit amet velit.\n",
             "\n",
             "2.  Suspendisse id sem consectetuer libero luctus adipiscing.\n"),

        para("It looks nice if you indent every line of the subsequent\n" +
             "paragraphs, but here again, Markdown will allow you to be\n" +
             "lazy:"),

        verb("*   This is a list item with two paragraphs.\n",
             "\n",
             "    This is the second paragraph in the list item. You're\n",
             "only required to indent the first line. Lorem ipsum dolor\n",
             "sit amet, consectetuer adipiscing elit.\n",
             "\n",
             "*   Another item in the same list.\n"),

        para("To put a blockquote within a list item, the blockquote's <code>></code>\n" +
             "delimiters need to be indented:"),

        verb("*   A list item with a blockquote:\n",
             "\n",
             "    > This is a blockquote\n",
             "    > inside a list item.\n"),

        para(
             "To put a code block within a list item, the code block needs\n" +
             "to be indented _twice_ -- 8 spaces or two tabs:"),

        verb("*   A list item with a code block:\n",
             "\n",
             "        <code goes here>\n"),

        para("It's worth noting that it's possible to trigger an ordered list by\n" +
             "accident, by writing something like this:"),

        verb("1986. What a great season.\n"),

        para("In other words, a <em>number-period-space</em> sequence at the beginning of a\n" +
             "line. To avoid this, you can backslash-escape the period:"),

        verb("1986\\. What a great season.\n"),

        raw("<h3 id=\"precode\">Code Blocks</h3>"),

        para("Pre-formatted code blocks are used for writing about programming or\n" +
             "markup source code. Rather than forming normal paragraphs, the lines\n" +
             "of a code block are interpreted literally. Markdown wraps a code block\n" +
             "in both <code><pre></code> and <code><code></code> tags."),

        para("To produce a code block in Markdown, simply indent every line of the\n" +
             "block by at least 4 spaces or 1 tab. For example, given this input:"),

        verb("This is a normal paragraph:\n",
             "\n",
             "    This is a code block.\n"),

        para("Markdown will generate:"),

        verb("<p>This is a normal paragraph:</p>\n",
             "\n",
             "<pre><code>This is a code block.\n",
             "</code></pre>\n"),

        para("One level of indentation -- 4 spaces or 1 tab -- is removed from each\n" +
             "line of the code block. For example, this:"),

        verb("Here is an example of AppleScript:\n",
             "\n",
             "    tell application \"Foo\"\n",
             "        beep\n",
             "    end tell\n"),

        para("will turn into:"),

        verb("<p>Here is an example of AppleScript:</p>\n",
             "\n",
             "<pre><code>tell application \"Foo\"\n",
             "    beep\n",
             "end tell\n",
             "</code></pre>\n"),

        para("A code block continues until it reaches a line that is not indented\n" +
             "(or the end of the article)."),

        para("Within a code block, ampersands (<code>&</code>) and angle brackets (<code><</code> and <code>></code>)\n" +
             "are automatically converted into HTML entities. This makes it very\n" +
             "easy to include example HTML source code using Markdown -- just paste\n" +
             "it and indent it, and Markdown will handle the hassle of encoding the\n" +
             "ampersands and angle brackets. For example, this:"),

        verb("    <div class=\"footer\">\n",
             "        &copy; 2004 Foo Corporation\n",
             "    </div>\n"),

        para("will turn into:"),

        verb("<pre><code>&lt;div class=\"footer\"&gt;\n",
             "    &amp;copy; 2004 Foo Corporation\n",
             "&lt;/div&gt;\n",
             "</code></pre>\n"),

        para("Regular Markdown syntax is not processed within code blocks. E.g.,\n" +
             "asterisks are just literal asterisks within a code block. This means\n" +
             "it's also easy to use Markdown to write about Markdown's own syntax."),

        raw("<h3 id=\"hr\">Horizontal Rules</h3>"),

        para("You can produce a horizontal rule tag (<code><hr /></code>) by placing three or\n" +
             "more hyphens, asterisks, or underscores on a line by themselves. If you\n" +
             "wish, you may use spaces between the hyphens or asterisks. Each of the\n" +
             "following lines will produce a horizontal rule:"),

        verb("* * *\n",
             "\n",
             "***\n",
             "\n",
             "*****\n",
             "\n",
             "- - -\n",
             "\n",
             "---------------------------------------\n",
             "\n",
             "_ _ _\n"),

        rule(1),

        raw("<h2 id=\"span\">Span Elements</h2>"),

        raw("<h3 id=\"link\">Links</h3>"),

        para("Markdown supports two style of links: _inline_ and _reference_."),

        para("In both styles, the link text is delimited by [square brackets]."),

        para("To create an inline link, use a set of regular parentheses immediately\n" +
             "after the link text's closing square bracket. Inside the parentheses,\n" +
             "put the URL where you want the link to point, along with an _optional_\n" +
             "title for the link, surrounded in quotes. For example:"),

        verb("This is [an example](http://example.com/ \"Title\") inline link.\n",
             "\n",
             "[This link](http://example.net/) has no title attribute.\n"),

        para("Will produce:"),

        verb("<p>This is <a href=\"http://example.com/\" title=\"Title\">\n",
             "an example</a> inline link.</p>\n",
             "\n",
             "<p><a href=\"http://example.net/\">This link</a> has no\n",
             "title attribute.</p>\n"),

        para("If you're referring to a local resource on the same server, you can\n" +
             "use relative paths:"),

        verb("See my [About](/about/) page for details.\n"),

        para("Reference-style links use a second set of square brackets, inside\n" +
             "which you place a label of your choosing to identify the link:"),

        verb("This is [an example][id] reference-style link.\n"),

        para("You can optionally use a space to separate the sets of brackets:"),

        verb("This is [an example] [id] reference-style link.\n"),

        para("Then, anywhere in the document, you define your link label like this,\n" +
             "on a line by itself:"),

        verb("[id]: http://example.com/  \"Optional Title Here\"\n"),

        para("That is:"),

        list(:BULLET,
          item(nil,
            para("Square brackets containing the link identifier (optionally\n" +
                 "indented from the left margin using up to three spaces);")),
          item(nil,
            para("followed by a colon;")),
          item(nil,
            para("followed by one or more spaces (or tabs);")),
          item(nil,
            para("followed by the URL for the link;")),
          item(nil,
            para("optionally followed by a title attribute for the link, enclosed\n" +
                 "in double or single quotes."))),

        para("The link URL may, optionally, be surrounded by angle brackets:"),

        verb("[id]: <http://example.com/>  \"Optional Title Here\"\n"),

        para("You can put the title attribute on the next line and use extra spaces\n" +
             "or tabs for padding, which tends to look better with longer URLs:"),

        verb("[id]: http://example.com/longish/path/to/resource/here\n",
             "    \"Optional Title Here\"\n"),

        para("Link definitions are only used for creating links during Markdown\n" +
             "processing, and are stripped from your document in the HTML output."),

        para("Link definition names may consist of letters, numbers, spaces, and punctuation -- but they are _not_ case sensitive. E.g. these two links:"),

        verb("[link text][a]\n",
             "[link text][A]\n"),

        para("are equivalent."),

        para("The <em>implicit link name</em> shortcut allows you to omit the name of the\n" +
             "link, in which case the link text itself is used as the name.\n" +
             "Just use an empty set of square brackets -- e.g., to link the word\n" +
             "\"Google\" to the google.com web site, you could simply write:"),

        verb("[Google][]\n"),

        para("And then define the link:"),

        verb("[Google]: http://google.com/\n"),

        para("Because link names may contain spaces, this shortcut even works for\n" +
            "multiple words in the link text:"),


        verb("Visit [Daring Fireball][] for more information.\n"),

        para("And then define the link:"),

        verb("[Daring Fireball]: http://daringfireball.net/\n"),

        para("Link definitions can be placed anywhere in your Markdown document. I\n" +
             "tend to put them immediately after each paragraph in which they're\n" +
             "used, but if you want, you can put them all at the end of your\n" +
             "document, sort of like footnotes."),

        para("Here's an example of reference links in action:"),

        verb("I get 10 times more traffic from [Google] [1] than from\n",
             "[Yahoo] [2] or [MSN] [3].\n",
             "\n",
             "  [1]: http://google.com/        \"Google\"\n",
             "  [2]: http://search.yahoo.com/  \"Yahoo Search\"\n",
             "  [3]: http://search.msn.com/    \"MSN Search\"\n"),

        para("Using the implicit link name shortcut, you could instead write:"),

        verb("I get 10 times more traffic from [Google][] than from\n",
             "[Yahoo][] or [MSN][].\n",
             "\n",
             "  [google]: http://google.com/        \"Google\"\n",
             "  [yahoo]:  http://search.yahoo.com/  \"Yahoo Search\"\n",
             "  [msn]:    http://search.msn.com/    \"MSN Search\"\n"),

        para("Both of the above examples will produce the following HTML output:"),

        verb("<p>I get 10 times more traffic from <a href=\"http://google.com/\"\n",
             "title=\"Google\">Google</a> than from\n",
             "<a href=\"http://search.yahoo.com/\" title=\"Yahoo Search\">Yahoo</a>\n",
             "or <a href=\"http://search.msn.com/\" title=\"MSN Search\">MSN</a>.</p>\n"),

        para("For comparison, here is the same paragraph written using\n" +
             "Markdown's inline link style:"),

        verb("I get 10 times more traffic from [Google](http://google.com/ \"Google\")\n",
             "than from [Yahoo](http://search.yahoo.com/ \"Yahoo Search\") or\n",
             "[MSN](http://search.msn.com/ \"MSN Search\").\n"),

        para("The point of reference-style links is not that they're easier to\n" +
             "write. The point is that with reference-style links, your document\n" +
             "source is vastly more readable. Compare the above examples: using\n" +
             "reference-style links, the paragraph itself is only 81 characters\n" +
             "long; with inline-style links, it's 176 characters; and as raw HTML,\n" +
             "it's 234 characters. In the raw HTML, there's more markup than there\n" +
             "is text."),

        para("With Markdown's reference-style links, a source document much more\n" +
             "closely resembles the final output, as rendered in a browser. By\n" +
             "allowing you to move the markup-related metadata out of the paragraph,\n" +
             "you can add links without interrupting the narrative flow of your\n" +
             "prose."),

        raw("<h3 id=\"em\">Emphasis</h3>"),

        para("Markdown treats asterisks (<code>*</code>) and underscores (<code>_</code>) as indicators of\n" +
             "emphasis. Text wrapped with one <code>*</code> or <code>_</code> will be wrapped with an\n" +
             "HTML <code><em></code> tag; double <code>*</code>'s or <code>_</code>'s will be wrapped with an HTML\n" +
             "<code><strong></code> tag. E.g., this input:"),

        verb("*single asterisks*\n",
             "\n",
             "_single underscores_\n",
             "\n",
             "**double asterisks**\n",
             "\n",
             "__double underscores__\n"),

        para("will produce:"),

        verb("<em>single asterisks</em>\n",
             "\n",
             "<em>single underscores</em>\n",
             "\n",
             "<strong>double asterisks</strong>\n",
             "\n",
             "<strong>double underscores</strong>\n"),

        para("You can use whichever style you prefer; the lone restriction is that\n" +
             "the same character must be used to open and close an emphasis span."),

        para("Emphasis can be used in the middle of a word:"),

        verb("un*fucking*believable\n"),

        para("But if you surround an <code>*</code> or <code>_</code> with spaces, it'll be treated as a\n" +
             "literal asterisk or underscore."),

        para("To produce a literal asterisk or underscore at a position where it\n" +
             "would otherwise be used as an emphasis delimiter, you can backslash\n" +
             "escape it:"),

        verb("\\*this text is surrounded by literal asterisks\\*\n"),

        raw("<h3 id=\"code\">Code</h3>"),

        para("To indicate a span of code, wrap it with backtick quotes (<code>`</code>).\n" +
             "Unlike a pre-formatted code block, a code span indicates code within a\n" +
             "normal paragraph. For example:"),

        verb("Use the `printf()` function.\n"),

        para("will produce:"),

        verb("<p>Use the <code>printf()</code> function.</p>\n"),

        para("To include a literal backtick character within a code span, you can use\n" +
             "multiple backticks as the opening and closing delimiters:"),

        verb("``There is a literal backtick (`) here.``\n"),

        para("which will produce this:"),

        verb("<p><code>There is a literal backtick (`) here.</code></p>\n"),

        para("The backtick delimiters surrounding a code span may include spaces --\n" +
             "one after the opening, one before the closing. This allows you to place\n" +
             "literal backtick characters at the beginning or end of a code span:"),

        verb("A single backtick in a code span: `` ` ``\n",
             "\n",
             "A backtick-delimited string in a code span: `` `foo` ``\n"),

        para("will produce:"),

        verb("<p>A single backtick in a code span: <code>`</code></p>\n",
             "\n",
             "<p>A backtick-delimited string in a code span: <code>`foo`</code></p>\n"),

        para("With a code span, ampersands and angle brackets are encoded as HTML\n" +
             "entities automatically, which makes it easy to include example HTML\n" +
             "tags. Markdown will turn this:"),

        verb("Please don't use any `<blink>` tags.\n"),

        para("into:"),

        verb("<p>Please don't use any <code>&lt;blink&gt;</code> tags.</p>\n"),

        para("You can write this:"),

        verb("`&#8212;` is the decimal-encoded equivalent of `&mdash;`.\n"),

        para("to produce:"),

        verb( "<p><code>&amp;#8212;</code> is the decimal-encoded\n",
             "equivalent of <code>&amp;mdash;</code>.</p>\n"),

        raw("<h3 id=\"img\">Images</h3>"),

        para("Admittedly, it's fairly difficult to devise a \"natural\" syntax for\n" +
             "placing images into a plain text document format."),

        para("Markdown uses an image syntax that is intended to resemble the syntax\n" +
             "for links, allowing for two styles: _inline_ and _reference_."),

        para("Inline image syntax looks like this:"),

        verb("![Alt text](/path/to/img.jpg)\n",
             "\n",
             "![Alt text](/path/to/img.jpg \"Optional title\")\n"),

        para("That is:"),

        list(:BULLET,
          item(nil,
            para("An exclamation mark: <code>!</code>;")),
          item(nil,
            para("followed by a set of square brackets, containing the <code>alt</code>\n" +
                 "attribute text for the image;")),
          item(nil,
            para("followed by a set of parentheses, containing the URL or path to\n" +
                 "the image, and an optional <code>title</code> attribute enclosed in double\n" +
                 "or single quotes."))),

        para("Reference-style image syntax looks like this:"),

        verb("![Alt text][id]\n"),

        para("Where \"id\" is the name of a defined image reference. Image references\n" +
             "are defined using syntax identical to link references:"),

        verb("[id]: url/to/image  \"Optional title attribute\"\n"),

        para("As of this writing, Markdown has no syntax for specifying the\n" +
             "dimensions of an image; if this is important to you, you can simply\n" +
             "use regular HTML <code><img></code> tags."),

        rule(1),

        raw("<h2 id=\"misc\">Miscellaneous</h2>"),

        raw("<h3 id=\"autolink\">Automatic Links</h3>"),

        para("Markdown supports a shortcut style for creating \"automatic\" links for URLs and email addresses: simply surround the URL or email address with angle brackets. What this means is that if you want to show the actual text of a URL or email address, and also have it be a clickable link, you can do this:"),

        verb("<http://example.com/>\n"),

        para("Markdown will turn this into:"),

        verb("<a href=\"http://example.com/\">http://example.com/</a>\n"),

        para("Automatic links for email addresses work similarly, except that\n" +
             "Markdown will also perform a bit of randomized decimal and hex\n" +
             "entity-encoding to help obscure your address from address-harvesting\n" +
             "spambots. For example, Markdown will turn this:"),

        verb("<address@example.com>\n"),

        para("into something like this:"),

        verb("<a href=\"&#x6D;&#x61;i&#x6C;&#x74;&#x6F;:&#x61;&#x64;&#x64;&#x72;&#x65;\n",
             "&#115;&#115;&#64;&#101;&#120;&#x61;&#109;&#x70;&#x6C;e&#x2E;&#99;&#111;\n",
             "&#109;\">&#x61;&#x64;&#x64;&#x72;&#x65;&#115;&#115;&#64;&#101;&#120;&#x61;\n",
             "&#109;&#x70;&#x6C;e&#x2E;&#99;&#111;&#109;</a>\n"),

        para("which will render in a browser as a clickable link to \"address@example.com\"."),

        para("(This sort of entity-encoding trick will indeed fool many, if not\n" +
               "most, address-harvesting bots, but it definitely won't fool all of\n" +
               "them. It's better than nothing, but an address published in this way\n" +
               "will probably eventually start receiving spam.)"),

        raw("<h3 id=\"backslash\">Backslash Escapes</h3>"),

        para("Markdown allows you to use backslash escapes to generate literal\n" +
             "characters which would otherwise have special meaning in Markdown's\n" +
             "formatting syntax. For example, if you wanted to surround a word with\n" +
             "literal asterisks (instead of an HTML <code><em></code> tag), you can backslashes\n" +
             "before the asterisks, like this:"),

        verb("\\*literal asterisks\\*\n"),

        para("Markdown provides backslash escapes for the following characters:"),

        verb("\\   backslash\n",
             "`   backtick\n",
             "*   asterisk\n",
             "_   underscore\n",
             "{}  curly braces\n",
             "[]  square brackets\n",
             "()  parentheses\n",
             "#   hash mark\n",
             "+	plus sign\n",
             "-	minus sign (hyphen)\n",
             ".   dot\n",
             "!   exclamation mark\n"))

    assert_equal expected, doc
  end

  def test_nested_blockquotes
    input = File.read "#{MARKDOWN_TEST_PATH}/Nested blockquotes.text"

    doc = @parser.parse input

    expected =
      doc(
        block(
          para("foo"),
          block(
            para("bar")),
          para("foo")))

    assert_equal expected, doc
  end

  def test_ordered_and_unordered_lists
    input = File.read "#{MARKDOWN_TEST_PATH}/Ordered and unordered lists.text"

    doc = @parser.parse input

    expected =
      doc(
        head(2, 'Unordered'),

        para('Asterisks tight:'),
        list(:BULLET,
          item(nil, para("asterisk 1")),
          item(nil, para("asterisk 2")),
          item(nil, para("asterisk 3"))),
        para('Asterisks loose:'),
        list(:BULLET,
          item(nil, para("asterisk 1")),
          item(nil, para("asterisk 2")),
          item(nil, para("asterisk 3"))),

        rule(1),

        para("Pluses tight:"),
        list(:BULLET,
          item(nil, para("Plus 1")),
          item(nil, para("Plus 2")),
          item(nil, para("Plus 3"))),
        para("Pluses loose:"),
        list(:BULLET,
          item(nil, para("Plus 1")),
          item(nil, para("Plus 2")),
          item(nil, para("Plus 3"))),

        rule(1),

        para("Minuses tight:"),
        list(:BULLET,
          item(nil, para("Minus 1")),
          item(nil, para("Minus 2")),
          item(nil, para("Minus 3"))),
        para("Minuses loose:"),
        list(:BULLET,
          item(nil, para("Minus 1")),
          item(nil, para("Minus 2")),
          item(nil, para("Minus 3"))),

        head(2, "Ordered"),

        para("Tight:"),
        list(:NUMBER,
          item(nil, para("First")),
          item(nil, para("Second")),
          item(nil, para("Third"))),
        para("and:"),
        list(:NUMBER,
          item(nil, para("One")),
          item(nil, para("Two")),
          item(nil, para("Three"))),

        para("Loose using tabs:"),
        list(:NUMBER,
          item(nil, para("First")),
          item(nil, para("Second")),
          item(nil, para("Third"))),
        para("and using spaces:"),
        list(:NUMBER,
          item(nil, para("One")),
          item(nil, para("Two")),
          item(nil, para("Three"))),

        para("Multiple paragraphs:"),
        list(:NUMBER,
          item(nil,
            para("Item 1, graf one."),
            para("Item 2. graf two. The quick brown fox " +
                 "jumped over the lazy dog's\nback.")),
          item(nil, para("Item 2.")),
          item(nil, para("Item 3."))),

        head(2, "Nested"),
        list(:BULLET,
          item(nil,
            para("Tab"),
            list(:BULLET,
              item(nil,
                para("Tab"),
                list(:BULLET,
                  item(nil,
                    para("Tab"))))))),

        para("Here's another:"),
        list(:NUMBER,
          item(nil, para("First")),
          item(nil, para("Second:"),
            list(:BULLET,
              item(nil, para("Fee")),
              item(nil, para("Fie")),
              item(nil, para("Foe")))),
          item(nil, para("Third"))),

        para("Same thing but with paragraphs:"),
        list(:NUMBER,
          item(nil, para("First")),
          item(nil, para("Second:"),
            list(:BULLET,
              item(nil, para("Fee")),
              item(nil, para("Fie")),
              item(nil, para("Foe")))),
          item(nil, para("Third"))),

        para("This was an error in Markdown 1.0.1:"),
        list(:BULLET,
          item(nil,
            para("this"),
            list(:BULLET,
              item(nil, para("sub"))),
            para("that"))))

    assert_equal expected, doc
  end

  def test_strong_and_em_together
    input = File.read "#{MARKDOWN_TEST_PATH}/Strong and em together.text"

    doc = @parser.parse input

    expected =
      doc(
        para("<b><em>This is strong and em.</em></b>"),
        para("So is <b>_this_</b> word."),
        para("<b><em>This is strong and em.</em></b>"),
        para("So is <b>_this_</b> word."))

    assert_equal expected, doc
  end

  def test_tabs
    input = File.read "#{MARKDOWN_TEST_PATH}/Tabs.text"

    doc = @parser.parse input

    expected =
      doc(
        list(:BULLET,
          item(nil,
            para("this is a list item\nindented with tabs")),
          item(nil,
            para("this is a list item\nindented with spaces"))),

        para("Code:"),

        verb("this code block is indented by one tab\n"),

        para("And:"),

        verb("\tthis code block is indented by two tabs\n"),

        para("And:"),

        verb(
          "+\tthis is an example list item\n",
          "\tindented with tabs\n",
          "\n",
          "+   this is an example list item\n",
          "    indented with spaces\n"))

    assert_equal expected, doc
  end

  def test_tidiness
    input = File.read "#{MARKDOWN_TEST_PATH}/Tidiness.text"

    doc = @parser.parse input

    expected =
      doc(
        block(
          para("A list within a blockquote:"),
          list(:BULLET,
            item(nil, para("asterisk 1")),
            item(nil, para("asterisk 2")),
            item(nil, para("asterisk 3")))))

    assert_equal expected, doc
  end

end
