# frozen_string_literal: true
require_relative 'helper'

class TestRDocMarkupToHtml < RDoc::Markup::FormatterTestCase

  add_visitor_tests

  def setup
    super

    @to = RDoc::Markup::ToHtml.new @options
  end

  def accept_blank_line
    assert_empty @to.res.join
  end

  def accept_block_quote
    assert_equal "\n<blockquote>\n<p>quote</p>\n</blockquote>\n", @to.res.join
  end

  def accept_document
    assert_equal "\n<p>hello</p>\n", @to.res.join
  end

  def accept_heading
    links = '<span><a href="#label-Hello">&para;</a> ' +
            '<a href="#top">&uarr;</a></span>'
    expected = "\n<h5 id=\"label-Hello\">Hello#{links}</h5>\n"

    assert_equal expected, @to.res.join
  end

  def accept_heading_1
    links = '<span><a href="#label-Hello">&para;</a> ' +
            '<a href="#top">&uarr;</a></span>'

    assert_equal "\n<h1 id=\"label-Hello\">Hello#{links}</h1>\n", @to.res.join
  end

  def accept_heading_2
    links = '<span><a href="#label-Hello">&para;</a> ' +
            '<a href="#top">&uarr;</a></span>'

    assert_equal "\n<h2 id=\"label-Hello\">Hello#{links}</h2>\n", @to.res.join
  end

  def accept_heading_3
    links = '<span><a href="#label-Hello">&para;</a> ' +
            '<a href="#top">&uarr;</a></span>'

    assert_equal "\n<h3 id=\"label-Hello\">Hello#{links}</h3>\n", @to.res.join
  end

  def accept_heading_4
    links = '<span><a href="#label-Hello">&para;</a> ' +
            '<a href="#top">&uarr;</a></span>'

    assert_equal "\n<h4 id=\"label-Hello\">Hello#{links}</h4>\n", @to.res.join
  end

  def accept_heading_b
    links = '<span><a href="#label-Hello">&para;</a> ' +
            '<a href="#top">&uarr;</a></span>'
    inner = "<strong>Hello</strong>"

    assert_equal "\n<h1 id=\"label-Hello\">#{inner}#{links}</h1>\n",
                 @to.res.join
  end

  def accept_heading_suppressed_crossref
    links = '<span><a href="#label-Hello">&para;</a> ' +
            '<a href="#top">&uarr;</a></span>'

    assert_equal "\n<h1 id=\"label-Hello\">Hello#{links}</h1>\n", @to.res.join
  end

  def accept_list_end_bullet
    assert_equal [], @to.list
    assert_equal [], @to.in_list_entry

    assert_equal "<ul></ul>\n", @to.res.join
  end

  def accept_list_end_label
    assert_equal [], @to.list
    assert_equal [], @to.in_list_entry

    assert_equal "<dl class=\"rdoc-list label-list\"></dl>\n", @to.res.join
  end

  def accept_list_end_lalpha
    assert_equal [], @to.list
    assert_equal [], @to.in_list_entry

    assert_equal "<ol style=\"list-style-type: lower-alpha\"></ol>\n", @to.res.join
  end

  def accept_list_end_number
    assert_equal [], @to.list
    assert_equal [], @to.in_list_entry

    assert_equal "<ol></ol>\n", @to.res.join
  end

  def accept_list_end_note
    assert_equal [], @to.list
    assert_equal [], @to.in_list_entry

    assert_equal "<dl class=\"rdoc-list note-list\"></dl>\n", @to.res.join
  end

  def accept_list_end_ualpha
    assert_equal [], @to.list
    assert_equal [], @to.in_list_entry

    assert_equal "<ol style=\"list-style-type: upper-alpha\"></ol>\n", @to.res.join
  end

  def accept_list_item_end_bullet
    assert_equal %w[</li>], @to.in_list_entry
  end

  def accept_list_item_end_label
    assert_equal %w[</dd>], @to.in_list_entry
  end

  def accept_list_item_end_lalpha
    assert_equal %w[</li>], @to.in_list_entry
  end

  def accept_list_item_end_note
    assert_equal %w[</dd>], @to.in_list_entry
  end

  def accept_list_item_end_number
    assert_equal %w[</li>], @to.in_list_entry
  end

  def accept_list_item_end_ualpha
    assert_equal %w[</li>], @to.in_list_entry
  end

  def accept_list_item_start_bullet
    assert_equal "<ul><li>", @to.res.join
  end

  def accept_list_item_start_label
    assert_equal "<dl class=\"rdoc-list label-list\"><dt>cat\n<dd>", @to.res.join
  end

  def accept_list_item_start_lalpha
    assert_equal "<ol style=\"list-style-type: lower-alpha\"><li>", @to.res.join
  end

  def accept_list_item_start_note
    assert_equal "<dl class=\"rdoc-list note-list\"><dt>cat\n<dd>",
                 @to.res.join
  end

  def accept_list_item_start_note_2
    expected = <<-EXPECTED
<dl class="rdoc-list note-list"><dt><code>teletype</code>
<dd>
<p>teletype description</p>
</dd></dl>
    EXPECTED

    assert_equal expected, @to.res.join
  end

  def accept_list_item_start_note_multi_description
    expected = <<-EXPECTED
<dl class="rdoc-list note-list"><dt>label
<dd>
<p>description one</p>
</dd><dd>
<p>description two</p>
</dd></dl>
    EXPECTED

    assert_equal expected, @to.res.join
  end

  def accept_list_item_start_note_multi_label
    expected = <<-EXPECTED
<dl class="rdoc-list note-list"><dt>one
<dt>two
<dd>
<p>two headers</p>
</dd></dl>
    EXPECTED

    assert_equal expected, @to.res.join
  end

  def accept_list_item_start_number
    assert_equal "<ol><li>", @to.res.join
  end

  def accept_list_item_start_ualpha
    assert_equal "<ol style=\"list-style-type: upper-alpha\"><li>", @to.res.join
  end

  def accept_list_start_bullet
    assert_equal [:BULLET], @to.list
    assert_equal [false], @to.in_list_entry

    assert_equal "<ul>", @to.res.join
  end

  def accept_list_start_label
    assert_equal [:LABEL], @to.list
    assert_equal [false], @to.in_list_entry

    assert_equal '<dl class="rdoc-list label-list">', @to.res.join
  end

  def accept_list_start_lalpha
    assert_equal [:LALPHA], @to.list
    assert_equal [false], @to.in_list_entry

    assert_equal "<ol style=\"list-style-type: lower-alpha\">", @to.res.join
  end

  def accept_list_start_note
    assert_equal [:NOTE], @to.list
    assert_equal [false], @to.in_list_entry

    assert_equal "<dl class=\"rdoc-list note-list\">", @to.res.join
  end

  def accept_list_start_number
    assert_equal [:NUMBER], @to.list
    assert_equal [false], @to.in_list_entry

    assert_equal "<ol>", @to.res.join
  end

  def accept_list_start_ualpha
    assert_equal [:UALPHA], @to.list
    assert_equal [false], @to.in_list_entry

    assert_equal "<ol style=\"list-style-type: upper-alpha\">", @to.res.join
  end

  def accept_paragraph
    assert_equal "\n<p>hi</p>\n", @to.res.join
  end

  def accept_paragraph_b
    assert_equal "\n<p>reg <strong>bold words</strong> reg</p>\n", @to.res.join
  end

  def accept_paragraph_br
    assert_equal "\n<p>one<br>two</p>\n", @to.res.join
  end

  def accept_paragraph_break
    assert_equal "\n<p>hello<br> world</p>\n", @to.res.join
  end

  def accept_paragraph_i
    assert_equal "\n<p>reg <em>italic words</em> reg</p>\n", @to.res.join
  end

  def accept_paragraph_plus
    assert_equal "\n<p>reg <code>teletype</code> reg</p>\n", @to.res.join
  end

  def accept_paragraph_star
    assert_equal "\n<p>reg <strong>bold</strong> reg</p>\n", @to.res.join
  end

  def accept_paragraph_underscore
    assert_equal "\n<p>reg <em>italic</em> reg</p>\n", @to.res.join
  end

  def accept_raw
    raw = <<-RAW.rstrip
<table>
<tr><th>Name<th>Count
<tr><td>a<td>1
<tr><td>b<td>2
</table>
    RAW

    assert_equal raw, @to.res.join
  end

  def accept_rule
    assert_equal "<hr>\n", @to.res.join
  end

  def accept_verbatim
    assert_equal "\n<pre class=\"ruby\"><span class=\"ruby-identifier\">hi</span>\n  <span class=\"ruby-identifier\">world</span>\n</pre>\n", @to.res.join
  end

  def end_accepting
    assert_equal 'hi', @to.end_accepting
  end

  def start_accepting
    assert_equal [], @to.res
    assert_equal [], @to.in_list_entry
    assert_equal [], @to.list
  end

  def list_nested
    expected = <<-EXPECTED
<ul><li>
<p>l1</p>
<ul><li>
<p>l1.1</p>
</li></ul>
</li><li>
<p>l2</p>
</li></ul>
    EXPECTED

    assert_equal expected, @to.res.join
  end

  def list_verbatim
    expected = <<-EXPECTED
<ul><li>
<p>list stuff</p>

<pre>* list
  with

  second

  1. indented
  2. numbered

  third

* second</pre>
</li></ul>
    EXPECTED

    assert_equal expected, @to.end_accepting
  end

  def test_accept_heading_7
    @to.start_accepting

    @to.accept_heading @RM::Heading.new(7, 'Hello')

    links = '<span><a href="#label-Hello">&para;</a> ' +
            '<a href="#top">&uarr;</a></span>'

    assert_equal "\n<h6 id=\"label-Hello\">Hello#{links}</h6>\n", @to.res.join
  end

  def test_accept_heading_aref_class
    @to.code_object = RDoc::NormalClass.new 'Foo'
    @to.start_accepting

    @to.accept_heading head(1, 'Hello')

    links = '<span><a href="#class-Foo-label-Hello">&para;</a> ' +
            '<a href="#top">&uarr;</a></span>'

    assert_equal "\n<h1 id=\"class-Foo-label-Hello\">Hello#{links}</h1>\n",
                 @to.res.join
  end

  def test_accept_heading_aref_method
    @to.code_object = RDoc::AnyMethod.new nil, 'foo'
    @to.start_accepting

    @to.accept_heading @RM::Heading.new(1, 'Hello')

    links = '<span><a href="#method-i-foo-label-Hello">&para;</a> ' +
            '<a href="#top">&uarr;</a></span>'

    assert_equal "\n<h1 id=\"method-i-foo-label-Hello\">Hello#{links}</h1>\n",
                 @to.res.join
  end

  def test_accept_heading_pipe
    @options.pipe = true

    @to.start_accepting

    @to.accept_heading @RM::Heading.new(1, 'Hello')

    assert_equal "\n<h1 id=\"label-Hello\">Hello</h1>\n", @to.res.join
  end

  def test_accept_paragraph_newline
    @to.start_accepting

    @to.accept_paragraph para("hello\n", "world\n")

    assert_equal "\n<p>hello world </p>\n", @to.res.join
  end

  def test_accept_heading_output_decoration
    @options.output_decoration = false

    @to.start_accepting

    @to.accept_heading @RM::Heading.new(1, 'Hello')

    assert_equal "\n<h1>Hello<span><a href=\"#label-Hello\">&para;</a> <a href=\"#top\">&uarr;</a></span></h1>\n", @to.res.join
  end

  def test_accept_heading_output_decoration_with_pipe
    @options.pipe = true
    @options.output_decoration = false

    @to.start_accepting

    @to.accept_heading @RM::Heading.new(1, 'Hello')

    assert_equal "\n<h1>Hello</h1>\n", @to.res.join
  end

  def test_accept_verbatim_parseable
    verb = @RM::Verbatim.new("class C\n", "end\n")

    @to.start_accepting
    @to.accept_verbatim verb

    expected = <<-EXPECTED

<pre class="ruby"><span class="ruby-keyword">class</span> <span class="ruby-constant">C</span>
<span class="ruby-keyword">end</span>
</pre>
    EXPECTED

    assert_equal expected, @to.res.join
  end

  def test_accept_verbatim_parseable_error
    verb = @RM::Verbatim.new("a % 09 # => blah\n")

    @to.start_accepting
    @to.accept_verbatim verb

    inner = CGI.escapeHTML "a % 09 # => blah"

    expected = <<-EXPECTED

<pre>#{inner}</pre>
    EXPECTED

    assert_equal expected, @to.res.join
  end

  def test_accept_verbatim_nl_after_backslash
    verb = @RM::Verbatim.new("a = 1 if first_flag_var and \\\n", "  this_is_flag_var\n")

    @to.start_accepting
    @to.accept_verbatim verb

    expected = <<-EXPECTED

<pre class="ruby"><span class="ruby-identifier">a</span> = <span class="ruby-value">1</span> <span class="ruby-keyword">if</span> <span class="ruby-identifier">first_flag_var</span> <span class="ruby-keyword">and</span> \\
  <span class="ruby-identifier">this_is_flag_var</span>
</pre>
    EXPECTED

    assert_equal expected, @to.res.join
  end

  def test_accept_verbatim_pipe
    @options.pipe = true

    verb = @RM::Verbatim.new("1 + 1\n")
    verb.format = :ruby

    @to.start_accepting
    @to.accept_verbatim verb

    expected = <<-EXPECTED

<pre><code>1 + 1
</code></pre>
    EXPECTED

    assert_equal expected, @to.res.join
  end

  def test_accept_verbatim_escape_in_string
    code = <<-'RUBY'
def foo
  [
    '\\',
    '\'',
    "'",
    "\'\"\`",
    "\#",
    "\#{}",
    "#",
    "#{}",
    /'"/,
    /\'\"/,
    /\//,
    /\\/,
    /\#/,
    /\#{}/,
    /#/,
    /#{}/
  ]
end
def bar
end
    RUBY
    verb = @RM::Verbatim.new(*code.split(/(?<=\n)/))

    @to.start_accepting
    @to.accept_verbatim verb

    expected = <<-'EXPECTED'

<pre class="ruby"><span class="ruby-keyword">def</span> <span class="ruby-identifier ruby-title">foo</span>
  [
    <span class="ruby-string">&#39;\\&#39;</span>,
    <span class="ruby-string">&#39;\&#39;&#39;</span>,
    <span class="ruby-string">&quot;&#39;&quot;</span>,
    <span class="ruby-string">&quot;\&#39;\&quot;\`&quot;</span>,
    <span class="ruby-string">&quot;\#&quot;</span>,
    <span class="ruby-string">&quot;\#{}&quot;</span>,
    <span class="ruby-string">&quot;#&quot;</span>,
    <span class="ruby-node">&quot;#{}&quot;</span>,
    <span class="ruby-regexp">/&#39;&quot;/</span>,
    <span class="ruby-regexp">/\&#39;\&quot;/</span>,
    <span class="ruby-regexp">/\//</span>,
    <span class="ruby-regexp">/\\/</span>,
    <span class="ruby-regexp">/\#/</span>,
    <span class="ruby-regexp">/\#{}/</span>,
    <span class="ruby-regexp">/#/</span>,
    <span class="ruby-regexp">/#{}/</span>
  ]
<span class="ruby-keyword">end</span>
<span class="ruby-keyword">def</span> <span class="ruby-identifier ruby-title">bar</span>
<span class="ruby-keyword">end</span>
</pre>
    EXPECTED

    assert_equal expected, @to.res.join
  end

  def test_accept_verbatim_escape_in_backtick
    code = <<-'RUBY'
def foo
  [
    `\\`,
    `\'\"\``,
    `\#`,
    `\#{}`,
    `#`,
    `#{}`
  ]
end
def bar
end
    RUBY
    verb = @RM::Verbatim.new(*code.split(/(?<=\n)/))

    @to.start_accepting
    @to.accept_verbatim verb

    expected = <<-'EXPECTED'

<pre class="ruby"><span class="ruby-keyword">def</span> <span class="ruby-identifier ruby-title">foo</span>
  [
    <span class="ruby-string">`\\`</span>,
    <span class="ruby-string">`\&#39;\&quot;\``</span>,
    <span class="ruby-string">`\#`</span>,
    <span class="ruby-string">`\#{}`</span>,
    <span class="ruby-string">`#`</span>,
    <span class="ruby-node">`#{}`</span>
  ]
<span class="ruby-keyword">end</span>
<span class="ruby-keyword">def</span> <span class="ruby-identifier ruby-title">bar</span>
<span class="ruby-keyword">end</span>
</pre>
    EXPECTED

    assert_equal expected, @to.res.join
  end

  def test_accept_verbatim_ruby
    verb = @RM::Verbatim.new("1 + 1\n")
    verb.format = :ruby

    @to.start_accepting
    @to.accept_verbatim verb

    expected = <<-EXPECTED

<pre class="ruby"><span class="ruby-value">1</span> <span class="ruby-operator">+</span> <span class="ruby-value">1</span>
</pre>
    EXPECTED

    assert_equal expected, @to.res.join
  end

  def test_accept_verbatim_redefinable_operators
    functions = %w[| ^ & <=> == === =~ > >= < <= << >> + - * / % ** ~ +@ -@ [] []= ` !  != !~].map { |redefinable_op|
      ["def #{redefinable_op}\n", "end\n"]
    }.flatten

    verb = @RM::Verbatim.new(*functions)

    @to.start_accepting
    @to.accept_verbatim verb

    expected = <<-EXPECTED

<pre class="ruby">
    EXPECTED
    expected = expected.rstrip

    %w[| ^ &amp; &lt;=&gt; == === =~ &gt; &gt;= &lt; &lt;= &lt;&lt; &gt;&gt; + - * / % ** ~ +@ -@ [] []= ` !  != !~].each do |html_escaped_op|
      expected += <<-EXPECTED
<span class="ruby-keyword">def</span> <span class="ruby-identifier ruby-title">#{html_escaped_op}</span>
<span class="ruby-keyword">end</span>
      EXPECTED
    end

    expected += <<-EXPECTED
</pre>
EXPECTED

    assert_equal expected, @to.res.join
  end

  def test_convert_string
    assert_equal '&lt;&gt;', @to.convert_string('<>')
  end

  def test_convert_HYPERLINK_irc
    result = @to.convert 'irc://irc.freenode.net/#ruby-lang'

    assert_equal "\n<p><a href=\"irc://irc.freenode.net/#ruby-lang\">irc.freenode.net/#ruby-lang</a></p>\n", result
  end

  def test_convert_RDOCLINK_label_label
    result = @to.convert 'rdoc-label:label-One'

    assert_equal "\n<p><a href=\"#label-One\">One</a></p>\n", result
  end

  def test_convert_RDOCLINK_label_foottext
    result = @to.convert 'rdoc-label:foottext-1'

    assert_equal "\n<p><a href=\"#foottext-1\">1</a></p>\n", result
  end

  def test_convert_RDOCLINK_label_footmark
    result = @to.convert 'rdoc-label:footmark-1'

    assert_equal "\n<p><a href=\"#footmark-1\">1</a></p>\n", result
  end

  def test_convert_RDOCLINK_ref
    result = @to.convert 'rdoc-ref:C'

    assert_equal "\n<p>C</p>\n", result
  end

  def test_convert_TIDYLINK_footnote
    result = @to.convert 'text{*1}[rdoc-label:foottext-1:footmark-1]'

    assert_equal "\n<p>text<sup><a id=\"footmark-1\" href=\"#foottext-1\">1</a></sup></p>\n", result
  end

  def test_convert_TIDYLINK_multiple
    result = @to.convert '{a}[http://example] {b}[http://example]'

    expected = <<-EXPECTED

<p><a href=\"http://example\">a</a> <a href=\"http://example\">b</a></p>
    EXPECTED

    assert_equal expected, result
  end

  def test_convert_TIDYLINK_image
    result =
      @to.convert '{rdoc-image:path/to/image.jpg}[http://example.com]'

    expected =
      "\n<p><a href=\"http://example.com\"><img src=\"path/to/image.jpg\"></a></p>\n"

    assert_equal expected, result
  end

  def test_convert_TIDYLINK_rdoc_label
    result = @to.convert '{foo}[rdoc-label:foottext-1]'

    assert_equal "\n<p><a href=\"#foottext-1\">foo</a></p>\n", result
  end

  def test_convert_TIDYLINK_irc
    result = @to.convert '{ruby-lang}[irc://irc.freenode.net/#ruby-lang]'

    assert_equal "\n<p><a href=\"irc://irc.freenode.net/#ruby-lang\">ruby-lang</a></p>\n", result
  end

  def test_convert_with_exclude_tag
    assert_equal "\n<p><code>aaa</code>[:symbol]</p>\n", @to.convert('+aaa+[:symbol]')
    assert_equal "\n<p><code>aaa[:symbol]</code></p>\n", @to.convert('+aaa[:symbol]+')
    assert_equal "\n<p><a href=\":symbol\">aaa</a></p>\n", @to.convert('aaa[:symbol]')
  end

  def test_convert_underscore_adjacent_to_code
    assert_equal "\n<p><code>aaa</code>_</p>\n", @to.convert(%q{+aaa+_})
    assert_equal "\n<p>\u{2018}<code>i386-mswin32_</code><em>MSRTVERSION</em>\u{2019}</p>\n", @to.convert(%q{`+i386-mswin32_+_MSRTVERSION_'})
  end

  def test_gen_url
    assert_equal '<a href="example">example</a>',
                 @to.gen_url('link:example', 'example')
  end

  def test_gen_url_rdoc_label
    assert_equal '<a href="#foottext-1">example</a>',
                 @to.gen_url('rdoc-label:foottext-1', 'example')
  end

  def test_gen_url_rdoc_label_id
    assert_equal '<sup><a id="footmark-1" href="#foottext-1">example</a></sup>',
                 @to.gen_url('rdoc-label:foottext-1:footmark-1', 'example')
  end

  def test_gen_url_image_url
    assert_equal '<img src="http://example.com/image.png" />', @to.gen_url('http://example.com/image.png', 'ignored')
  end

  def test_gen_url_ssl_image_url
    assert_equal '<img src="https://example.com/image.png" />', @to.gen_url('https://example.com/image.png', 'ignored')
  end

  def test_gen_url_rdoc_file
    assert_equal '<a href="example_rdoc.html">example</a>',
                 @to.gen_url('example.rdoc', 'example')
    assert_equal '<a href="doc/example_rdoc.html">example</a>',
                 @to.gen_url('doc/example.rdoc', 'example')
    assert_equal '<a href="../ex.doc/example_rdoc.html">example</a>',
                 @to.gen_url('../ex.doc/example.rdoc', 'example')
    assert_equal '<a href="doc/example_rdoc.html#label-one">example</a>',
                 @to.gen_url('doc/example.rdoc#label-one', 'example')
    assert_equal '<a href="../ex.doc/example_rdoc.html#label-two">example</a>',
                 @to.gen_url('../ex.doc/example.rdoc#label-two', 'example')
  end

  def test_gen_url_md_file
    assert_equal '<a href="example_md.html">example</a>',
                 @to.gen_url('example.md', 'example')
    assert_equal '<a href="doc/example_md.html">example</a>',
                 @to.gen_url('doc/example.md', 'example')
    assert_equal '<a href="../ex.doc/example_md.html">example</a>',
                 @to.gen_url('../ex.doc/example.md', 'example')
    assert_equal '<a href="doc/example_md.html#label-one">example</a>',
                 @to.gen_url('doc/example.md#label-one', 'example')
    assert_equal '<a href="../ex.doc/example_md.html#label-two">example</a>',
                 @to.gen_url('../ex.doc/example.md#label-two', 'example')
  end

  def test_gen_url_rb_file
    assert_equal '<a href="example_rb.html">example</a>',
                 @to.gen_url('example.rb', 'example')
    assert_equal '<a href="doc/example_rb.html">example</a>',
                 @to.gen_url('doc/example.rb', 'example')
    assert_equal '<a href="../ex.doc/example_rb.html">example</a>',
                 @to.gen_url('../ex.doc/example.rb', 'example')
    assert_equal '<a href="doc/example_rb.html#label-one">example</a>',
                 @to.gen_url('doc/example.rb#label-one', 'example')
    assert_equal '<a href="../ex.doc/example_rb.html#label-two">example</a>',
                 @to.gen_url('../ex.doc/example.rb#label-two', 'example')
  end

  def test_handle_regexp_HYPERLINK_link
    target = RDoc::Markup::RegexpHandling.new 0, 'link:README.txt'

    link = @to.handle_regexp_HYPERLINK target

    assert_equal '<a href="README.txt">README.txt</a>', link
  end

  def test_handle_regexp_HYPERLINK_irc
    target = RDoc::Markup::RegexpHandling.new 0, 'irc://irc.freenode.net/#ruby-lang'

    link = @to.handle_regexp_HYPERLINK target

    assert_equal '<a href="irc://irc.freenode.net/#ruby-lang">irc.freenode.net/#ruby-lang</a>', link
  end

  def test_list_verbatim_2
    str = "* one\n    verb1\n    verb2\n* two\n"

    expected = <<-EXPECTED
<ul><li>
<p>one</p>

<pre class=\"ruby\"><span class=\"ruby-identifier\">verb1</span>
<span class=\"ruby-identifier\">verb2</span>
</pre>
</li><li>
<p>two</p>
</li></ul>
    EXPECTED

    assert_equal expected, @m.convert(str, @to)
  end

  def test_parseable_eh
    valid_syntax = [
      'def x() end',
      'def x; end',
      'class C; end',
      "module M end",
      'a # => blah',
      'x { |y| nil }',
      'x do |y| nil end',
      '# only a comment',
      'require "foo"',
      'cls="foo"'
    ]
    invalid_syntax = [
      'def x end',
      'class C < end',
      'module M < C end',
      'a=># blah',
      'x { |y| ... }',
      'x do |y| ... end',
      '// only a comment',
      '<% require "foo" %>',
      'class="foo"'
    ]
    valid_syntax.each do |t|
      assert @to.parseable?(t), "valid syntax considered invalid: #{t}"
    end
    invalid_syntax.each do |t|
      refute @to.parseable?(t), "invalid syntax considered valid: #{t}"
    end
  end

  def test_to_html
    assert_equal "\n<p><code>--</code></p>\n", util_format("<tt>--</tt>")
  end

  def util_format text
    paragraph = RDoc::Markup::Paragraph.new text

    @to.start_accepting
    @to.accept_paragraph paragraph
    @to.end_accepting
  end

end

