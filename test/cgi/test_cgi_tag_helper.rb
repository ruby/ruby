require 'test/unit'
require 'cgi'
require 'stringio'
require_relative 'update_env'


class CGITagHelperTest < Test::Unit::TestCase
  include UpdateEnv


  def setup
    @environ = {}
    #@environ = {
    #  'SERVER_PROTOCOL' => 'HTTP/1.1',
    #  'REQUEST_METHOD'  => 'GET',
    #  'SERVER_SOFTWARE' => 'Apache 2.2.0',
    #}
    #ENV.update(@environ)
  end


  def teardown
    ENV.update(@environ)
    $stdout = STDOUT
  end


  def test_cgi_tag_helper_html3
    update_env(
      'REQUEST_METHOD' => 'GET',
    )
    ## html3
    cgi = CGI.new('html3')
    assert_equal('<A HREF=""></A>',cgi.a)
    assert_equal('<A HREF="bar"></A>',cgi.a('bar'))
    assert_equal('<A HREF="">foo</A>',cgi.a{'foo'})
    assert_equal('<A HREF="bar">foo</A>',cgi.a('bar'){'foo'})
    assert_equal('<TT></TT>',cgi.tt)
    assert_equal('<TT></TT>',cgi.tt('bar'))
    assert_equal('<TT>foo</TT>',cgi.tt{'foo'})
    assert_equal('<TT>foo</TT>',cgi.tt('bar'){'foo'})
    assert_equal('<I></I>',cgi.i)
    assert_equal('<I></I>',cgi.i('bar'))
    assert_equal('<I>foo</I>',cgi.i{'foo'})
    assert_equal('<I>foo</I>',cgi.i('bar'){'foo'})
    assert_equal('<B></B>',cgi.b)
    assert_equal('<B></B>',cgi.b('bar'))
    assert_equal('<B>foo</B>',cgi.b{'foo'})
    assert_equal('<B>foo</B>',cgi.b('bar'){'foo'})
    assert_equal('<U></U>',cgi.u)
    assert_equal('<U></U>',cgi.u('bar'))
    assert_equal('<U>foo</U>',cgi.u{'foo'})
    assert_equal('<U>foo</U>',cgi.u('bar'){'foo'})
    assert_equal('<STRIKE></STRIKE>',cgi.strike)
    assert_equal('<STRIKE></STRIKE>',cgi.strike('bar'))
    assert_equal('<STRIKE>foo</STRIKE>',cgi.strike{'foo'})
    assert_equal('<STRIKE>foo</STRIKE>',cgi.strike('bar'){'foo'})
    assert_equal('<BIG></BIG>',cgi.big)
    assert_equal('<BIG></BIG>',cgi.big('bar'))
    assert_equal('<BIG>foo</BIG>',cgi.big{'foo'})
    assert_equal('<BIG>foo</BIG>',cgi.big('bar'){'foo'})
    assert_equal('<SMALL></SMALL>',cgi.small)
    assert_equal('<SMALL></SMALL>',cgi.small('bar'))
    assert_equal('<SMALL>foo</SMALL>',cgi.small{'foo'})
    assert_equal('<SMALL>foo</SMALL>',cgi.small('bar'){'foo'})
    assert_equal('<SUB></SUB>',cgi.sub)
    assert_equal('<SUB></SUB>',cgi.sub('bar'))
    assert_equal('<SUB>foo</SUB>',cgi.sub{'foo'})
    assert_equal('<SUB>foo</SUB>',cgi.sub('bar'){'foo'})
    assert_equal('<SUP></SUP>',cgi.sup)
    assert_equal('<SUP></SUP>',cgi.sup('bar'))
    assert_equal('<SUP>foo</SUP>',cgi.sup{'foo'})
    assert_equal('<SUP>foo</SUP>',cgi.sup('bar'){'foo'})
    assert_equal('<EM></EM>',cgi.em)
    assert_equal('<EM></EM>',cgi.em('bar'))
    assert_equal('<EM>foo</EM>',cgi.em{'foo'})
    assert_equal('<EM>foo</EM>',cgi.em('bar'){'foo'})
    assert_equal('<STRONG></STRONG>',cgi.strong)
    assert_equal('<STRONG></STRONG>',cgi.strong('bar'))
    assert_equal('<STRONG>foo</STRONG>',cgi.strong{'foo'})
    assert_equal('<STRONG>foo</STRONG>',cgi.strong('bar'){'foo'})
    assert_equal('<DFN></DFN>',cgi.dfn)
    assert_equal('<DFN></DFN>',cgi.dfn('bar'))
    assert_equal('<DFN>foo</DFN>',cgi.dfn{'foo'})
    assert_equal('<DFN>foo</DFN>',cgi.dfn('bar'){'foo'})
    assert_equal('<CODE></CODE>',cgi.code)
    assert_equal('<CODE></CODE>',cgi.code('bar'))
    assert_equal('<CODE>foo</CODE>',cgi.code{'foo'})
    assert_equal('<CODE>foo</CODE>',cgi.code('bar'){'foo'})
    assert_equal('<SAMP></SAMP>',cgi.samp)
    assert_equal('<SAMP></SAMP>',cgi.samp('bar'))
    assert_equal('<SAMP>foo</SAMP>',cgi.samp{'foo'})
    assert_equal('<SAMP>foo</SAMP>',cgi.samp('bar'){'foo'})
    assert_equal('<KBD></KBD>',cgi.kbd)
    assert_equal('<KBD></KBD>',cgi.kbd('bar'))
    assert_equal('<KBD>foo</KBD>',cgi.kbd{'foo'})
    assert_equal('<KBD>foo</KBD>',cgi.kbd('bar'){'foo'})
    assert_equal('<VAR></VAR>',cgi.var)
    assert_equal('<VAR></VAR>',cgi.var('bar'))
    assert_equal('<VAR>foo</VAR>',cgi.var{'foo'})
    assert_equal('<VAR>foo</VAR>',cgi.var('bar'){'foo'})
    assert_equal('<CITE></CITE>',cgi.cite)
    assert_equal('<CITE></CITE>',cgi.cite('bar'))
    assert_equal('<CITE>foo</CITE>',cgi.cite{'foo'})
    assert_equal('<CITE>foo</CITE>',cgi.cite('bar'){'foo'})
    assert_equal('<FONT></FONT>',cgi.font)
    assert_equal('<FONT></FONT>',cgi.font('bar'))
    assert_equal('<FONT>foo</FONT>',cgi.font{'foo'})
    assert_equal('<FONT>foo</FONT>',cgi.font('bar'){'foo'})
    assert_equal('<ADDRESS></ADDRESS>',cgi.address)
    assert_equal('<ADDRESS></ADDRESS>',cgi.address('bar'))
    assert_equal('<ADDRESS>foo</ADDRESS>',cgi.address{'foo'})
    assert_equal('<ADDRESS>foo</ADDRESS>',cgi.address('bar'){'foo'})
    assert_equal('<DIV></DIV>',cgi.div)
    assert_equal('<DIV></DIV>',cgi.div('bar'))
    assert_equal('<DIV>foo</DIV>',cgi.div{'foo'})
    assert_equal('<DIV>foo</DIV>',cgi.div('bar'){'foo'})
    assert_equal('<CENTER></CENTER>',cgi.center)
    assert_equal('<CENTER></CENTER>',cgi.center('bar'))
    assert_equal('<CENTER>foo</CENTER>',cgi.center{'foo'})
    assert_equal('<CENTER>foo</CENTER>',cgi.center('bar'){'foo'})
    assert_equal('<MAP></MAP>',cgi.map)
    assert_equal('<MAP></MAP>',cgi.map('bar'))
    assert_equal('<MAP>foo</MAP>',cgi.map{'foo'})
    assert_equal('<MAP>foo</MAP>',cgi.map('bar'){'foo'})
    assert_equal('<APPLET></APPLET>',cgi.applet)
    assert_equal('<APPLET></APPLET>',cgi.applet('bar'))
    assert_equal('<APPLET>foo</APPLET>',cgi.applet{'foo'})
    assert_equal('<APPLET>foo</APPLET>',cgi.applet('bar'){'foo'})
    assert_equal('<PRE></PRE>',cgi.pre)
    assert_equal('<PRE></PRE>',cgi.pre('bar'))
    assert_equal('<PRE>foo</PRE>',cgi.pre{'foo'})
    assert_equal('<PRE>foo</PRE>',cgi.pre('bar'){'foo'})
    assert_equal('<XMP></XMP>',cgi.xmp)
    assert_equal('<XMP></XMP>',cgi.xmp('bar'))
    assert_equal('<XMP>foo</XMP>',cgi.xmp{'foo'})
    assert_equal('<XMP>foo</XMP>',cgi.xmp('bar'){'foo'})
    assert_equal('<LISTING></LISTING>',cgi.listing)
    assert_equal('<LISTING></LISTING>',cgi.listing('bar'))
    assert_equal('<LISTING>foo</LISTING>',cgi.listing{'foo'})
    assert_equal('<LISTING>foo</LISTING>',cgi.listing('bar'){'foo'})
    assert_equal('<DL></DL>',cgi.dl)
    assert_equal('<DL></DL>',cgi.dl('bar'))
    assert_equal('<DL>foo</DL>',cgi.dl{'foo'})
    assert_equal('<DL>foo</DL>',cgi.dl('bar'){'foo'})
    assert_equal('<OL></OL>',cgi.ol)
    assert_equal('<OL></OL>',cgi.ol('bar'))
    assert_equal('<OL>foo</OL>',cgi.ol{'foo'})
    assert_equal('<OL>foo</OL>',cgi.ol('bar'){'foo'})
    assert_equal('<UL></UL>',cgi.ul)
    assert_equal('<UL></UL>',cgi.ul('bar'))
    assert_equal('<UL>foo</UL>',cgi.ul{'foo'})
    assert_equal('<UL>foo</UL>',cgi.ul('bar'){'foo'})
    assert_equal('<DIR></DIR>',cgi.dir)
    assert_equal('<DIR></DIR>',cgi.dir('bar'))
    assert_equal('<DIR>foo</DIR>',cgi.dir{'foo'})
    assert_equal('<DIR>foo</DIR>',cgi.dir('bar'){'foo'})
    assert_equal('<MENU></MENU>',cgi.menu)
    assert_equal('<MENU></MENU>',cgi.menu('bar'))
    assert_equal('<MENU>foo</MENU>',cgi.menu{'foo'})
    assert_equal('<MENU>foo</MENU>',cgi.menu('bar'){'foo'})
    assert_equal('<SELECT></SELECT>',cgi.select)
    assert_equal('<SELECT></SELECT>',cgi.select('bar'))
    assert_equal('<SELECT>foo</SELECT>',cgi.select{'foo'})
    assert_equal('<SELECT>foo</SELECT>',cgi.select('bar'){'foo'})
    assert_equal('<TABLE></TABLE>',cgi.table)
    assert_equal('<TABLE></TABLE>',cgi.table('bar'))
    assert_equal('<TABLE>foo</TABLE>',cgi.table{'foo'})
    assert_equal('<TABLE>foo</TABLE>',cgi.table('bar'){'foo'})
    assert_equal('<TITLE></TITLE>',cgi.title)
    assert_equal('<TITLE></TITLE>',cgi.title('bar'))
    assert_equal('<TITLE>foo</TITLE>',cgi.title{'foo'})
    assert_equal('<TITLE>foo</TITLE>',cgi.title('bar'){'foo'})
    assert_equal('<STYLE></STYLE>',cgi.style)
    assert_equal('<STYLE></STYLE>',cgi.style('bar'))
    assert_equal('<STYLE>foo</STYLE>',cgi.style{'foo'})
    assert_equal('<STYLE>foo</STYLE>',cgi.style('bar'){'foo'})
    assert_equal('<SCRIPT></SCRIPT>',cgi.script)
    assert_equal('<SCRIPT></SCRIPT>',cgi.script('bar'))
    assert_equal('<SCRIPT>foo</SCRIPT>',cgi.script{'foo'})
    assert_equal('<SCRIPT>foo</SCRIPT>',cgi.script('bar'){'foo'})
    assert_equal('<H1></H1>',cgi.h1)
    assert_equal('<H1></H1>',cgi.h1('bar'))
    assert_equal('<H1>foo</H1>',cgi.h1{'foo'})
    assert_equal('<H1>foo</H1>',cgi.h1('bar'){'foo'})
    assert_equal('<H2></H2>',cgi.h2)
    assert_equal('<H2></H2>',cgi.h2('bar'))
    assert_equal('<H2>foo</H2>',cgi.h2{'foo'})
    assert_equal('<H2>foo</H2>',cgi.h2('bar'){'foo'})
    assert_equal('<H3></H3>',cgi.h3)
    assert_equal('<H3></H3>',cgi.h3('bar'))
    assert_equal('<H3>foo</H3>',cgi.h3{'foo'})
    assert_equal('<H3>foo</H3>',cgi.h3('bar'){'foo'})
    assert_equal('<H4></H4>',cgi.h4)
    assert_equal('<H4></H4>',cgi.h4('bar'))
    assert_equal('<H4>foo</H4>',cgi.h4{'foo'})
    assert_equal('<H4>foo</H4>',cgi.h4('bar'){'foo'})
    assert_equal('<H5></H5>',cgi.h5)
    assert_equal('<H5></H5>',cgi.h5('bar'))
    assert_equal('<H5>foo</H5>',cgi.h5{'foo'})
    assert_equal('<H5>foo</H5>',cgi.h5('bar'){'foo'})
    assert_equal('<H6></H6>',cgi.h6)
    assert_equal('<H6></H6>',cgi.h6('bar'))
    assert_equal('<H6>foo</H6>',cgi.h6{'foo'})
    assert_equal('<H6>foo</H6>',cgi.h6('bar'){'foo'})
    assert_match(/^<TEXTAREA .*><\/TEXTAREA>$/,cgi.textarea)
    assert_match(/COLS="70"/,cgi.textarea)
    assert_match(/ROWS="10"/,cgi.textarea)
    assert_match(/NAME=""/,cgi.textarea)
    assert_match(/^<TEXTAREA .*><\/TEXTAREA>$/,cgi.textarea("bar"))
    assert_match(/COLS="70"/,cgi.textarea("bar"))
    assert_match(/ROWS="10"/,cgi.textarea("bar"))
    assert_match(/NAME="bar"/,cgi.textarea("bar"))
    assert_match(/^<TEXTAREA .*>foo<\/TEXTAREA>$/,cgi.textarea{"foo"})
    assert_match(/COLS="70"/,cgi.textarea{"foo"})
    assert_match(/ROWS="10"/,cgi.textarea{"foo"})
    assert_match(/NAME=""/,cgi.textarea{"foo"})
    assert_match(/^<TEXTAREA .*>foo<\/TEXTAREA>$/,cgi.textarea("bar"){"foo"})
    assert_match(/COLS="70"/,cgi.textarea("bar"){"foo"})
    assert_match(/ROWS="10"/,cgi.textarea("bar"){"foo"})
    assert_match(/NAME="bar"/,cgi.textarea("bar"){"foo"})
    assert_match(/^<FORM .*><\/FORM>$/,cgi.form)
    assert_match(/METHOD="post"/,cgi.form)
    assert_match(/ENCTYPE="application\/x-www-form-urlencoded"/,cgi.form)
    assert_match(/^<FORM .*><\/FORM>$/,cgi.form("bar"))
    assert_match(/METHOD="bar"/,cgi.form("bar"))
    assert_match(/ENCTYPE="application\/x-www-form-urlencoded"/,cgi.form("bar"))
    assert_match(/^<FORM .*>foo<\/FORM>$/,cgi.form{"foo"})
    assert_match(/METHOD="post"/,cgi.form{"foo"})
    assert_match(/ENCTYPE="application\/x-www-form-urlencoded"/,cgi.form{"foo"})
    assert_match(/^<FORM .*>foo<\/FORM>$/,cgi.form("bar"){"foo"})
    assert_match(/METHOD="bar"/,cgi.form("bar"){"foo"})
    assert_match(/ENCTYPE="application\/x-www-form-urlencoded"/,cgi.form("bar"){"foo"})
    assert_equal('<BLOCKQUOTE></BLOCKQUOTE>',cgi.blockquote)
    assert_equal('<BLOCKQUOTE CITE="bar"></BLOCKQUOTE>',cgi.blockquote('bar'))
    assert_equal('<BLOCKQUOTE>foo</BLOCKQUOTE>',cgi.blockquote{'foo'})
    assert_equal('<BLOCKQUOTE CITE="bar">foo</BLOCKQUOTE>',cgi.blockquote('bar'){'foo'})
    assert_equal('<CAPTION></CAPTION>',cgi.caption)
    assert_equal('<CAPTION ALIGN="bar"></CAPTION>',cgi.caption('bar'))
    assert_equal('<CAPTION>foo</CAPTION>',cgi.caption{'foo'})
    assert_equal('<CAPTION ALIGN="bar">foo</CAPTION>',cgi.caption('bar'){'foo'})
    assert_equal('<IMG SRC="" ALT="">',cgi.img)
    assert_equal('<IMG SRC="bar" ALT="">',cgi.img('bar'))
    assert_equal('<IMG SRC="" ALT="">',cgi.img{'foo'})
    assert_equal('<IMG SRC="bar" ALT="">',cgi.img('bar'){'foo'})
    assert_equal('<BASE HREF="">',cgi.base)
    assert_equal('<BASE HREF="bar">',cgi.base('bar'))
    assert_equal('<BASE HREF="">',cgi.base{'foo'})
    assert_equal('<BASE HREF="bar">',cgi.base('bar'){'foo'})
    assert_equal('<BASEFONT>',cgi.basefont)
    assert_equal('<BASEFONT>',cgi.basefont('bar'))
    assert_equal('<BASEFONT>',cgi.basefont{'foo'})
    assert_equal('<BASEFONT>',cgi.basefont('bar'){'foo'})
    assert_equal('<BR>',cgi.br)
    assert_equal('<BR>',cgi.br('bar'))
    assert_equal('<BR>',cgi.br{'foo'})
    assert_equal('<BR>',cgi.br('bar'){'foo'})
    assert_equal('<AREA>',cgi.area)
    assert_equal('<AREA>',cgi.area('bar'))
    assert_equal('<AREA>',cgi.area{'foo'})
    assert_equal('<AREA>',cgi.area('bar'){'foo'})
    assert_equal('<LINK>',cgi.link)
    assert_equal('<LINK>',cgi.link('bar'))
    assert_equal('<LINK>',cgi.link{'foo'})
    assert_equal('<LINK>',cgi.link('bar'){'foo'})
    assert_equal('<PARAM>',cgi.param)
    assert_equal('<PARAM>',cgi.param('bar'))
    assert_equal('<PARAM>',cgi.param{'foo'})
    assert_equal('<PARAM>',cgi.param('bar'){'foo'})
    assert_equal('<HR>',cgi.hr)
    assert_equal('<HR>',cgi.hr('bar'))
    assert_equal('<HR>',cgi.hr{'foo'})
    assert_equal('<HR>',cgi.hr('bar'){'foo'})
    assert_equal('<INPUT>',cgi.input)
    assert_equal('<INPUT>',cgi.input('bar'))
    assert_equal('<INPUT>',cgi.input{'foo'})
    assert_equal('<INPUT>',cgi.input('bar'){'foo'})
    assert_equal('<ISINDEX>',cgi.isindex)
    assert_equal('<ISINDEX>',cgi.isindex('bar'))
    assert_equal('<ISINDEX>',cgi.isindex{'foo'})
    assert_equal('<ISINDEX>',cgi.isindex('bar'){'foo'})
    assert_equal('<META>',cgi.meta)
    assert_equal('<META>',cgi.meta('bar'))
    assert_equal('<META>',cgi.meta{'foo'})
    assert_equal('<META>',cgi.meta('bar'){'foo'})
    assert_equal('<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN"><HTML>',cgi.html)
    assert_equal('<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN"><HTML>foo</HTML>',cgi.html{'foo'})
    assert_equal('<HEAD>',cgi.head)
    assert_equal('<HEAD>foo</HEAD>',cgi.head{'foo'})
    assert_equal('<BODY>',cgi.body)
    assert_equal('<BODY>foo</BODY>',cgi.body{'foo'})
    assert_equal('<P>',cgi.p)
    assert_equal('<P>foo</P>',cgi.p{'foo'})
    assert_equal('<PLAINTEXT>',cgi.plaintext)
    assert_equal('<PLAINTEXT>foo</PLAINTEXT>',cgi.plaintext{'foo'})
    assert_equal('<DT>',cgi.dt)
    assert_equal('<DT>foo</DT>',cgi.dt{'foo'})
    assert_equal('<DD>',cgi.dd)
    assert_equal('<DD>foo</DD>',cgi.dd{'foo'})
    assert_equal('<LI>',cgi.li)
    assert_equal('<LI>foo</LI>',cgi.li{'foo'})
    assert_equal('<OPTION>',cgi.option)
    assert_equal('<OPTION>foo</OPTION>',cgi.option{'foo'})
    assert_equal('<TR>',cgi.tr)
    assert_equal('<TR>foo</TR>',cgi.tr{'foo'})
    assert_equal('<TH>',cgi.th)
    assert_equal('<TH>foo</TH>',cgi.th{'foo'})
    assert_equal('<TD>',cgi.td)
    assert_equal('<TD>foo</TD>',cgi.td{'foo'})
    str=cgi.checkbox_group("foo",["aa","bb"],["cc","dd"])
    assert_match(/^<INPUT .*VALUE="aa".*>bb<INPUT .*VALUE="cc".*>dd$/,str)
    assert_match(/^<INPUT .*TYPE="checkbox".*>bb<INPUT .*TYPE="checkbox".*>dd$/,str)
    assert_match(/^<INPUT .*NAME="foo".*>bb<INPUT .*NAME="foo".*>dd$/,str)
    str=cgi.radio_group("foo",["aa","bb"],["cc","dd"])
    assert_match(/^<INPUT .*VALUE="aa".*>bb<INPUT .*VALUE="cc".*>dd$/,str)
    assert_match(/^<INPUT .*TYPE="radio".*>bb<INPUT .*TYPE="radio".*>dd$/,str)
    assert_match(/^<INPUT .*NAME="foo".*>bb<INPUT .*NAME="foo".*>dd$/,str)
    str=cgi.checkbox_group("foo",["aa","bb"],["cc","dd",true])
    assert_match(/^<INPUT .*VALUE="aa".*>bb<INPUT .*VALUE="cc".*>dd$/,str)
    assert_match(/^<INPUT .*TYPE="checkbox".*>bb<INPUT .*TYPE="checkbox".*>dd$/,str)
    assert_match(/^<INPUT .*NAME="foo".*>bb<INPUT .*NAME="foo".*>dd$/,str)
    assert_match(/^<INPUT .*>bb<INPUT .*CHECKED.*>dd$/,str)
    assert_match(/<INPUT .*TYPE="text".*>/,cgi.text_field(:name=>"name",:value=>"value"))
    str=cgi.radio_group("foo",["aa","bb"],["cc","dd",false])
    assert_match(/^<INPUT .*VALUE="aa".*>bb<INPUT .*VALUE="cc".*>dd$/,str)
    assert_match(/^<INPUT .*TYPE="radio".*>bb<INPUT .*TYPE="radio".*>dd$/,str)
    assert_match(/^<INPUT .*NAME="foo".*>bb<INPUT .*NAME="foo".*>dd$/,str)
  end

=begin
  def test_cgi_tag_helper_html4
    ## html4
    cgi = CGI.new('html4')
    ## html4 transitional
    cgi = CGI.new('html4Tr')
    ## html4 frameset
    cgi = CGI.new('html4Fr')
  end
=end

  def test_cgi_tag_helper_html5
    update_env(
      'REQUEST_METHOD' => 'GET',
    )
    ## html5
    cgi = CGI.new('html5')
    assert_equal('<HEADER></HEADER>',cgi.header)
    assert_equal('<FOOTER></FOOTER>',cgi.footer)
    assert_equal('<ARTICLE></ARTICLE>',cgi.article)
    assert_equal('<SECTION></SECTION>',cgi.section)
    assert_equal('<!DOCTYPE HTML><HTML BLA="TEST"></HTML>',cgi.html("BLA"=>"TEST"){})
  end

end
