#
# test_scanner_events.rb
#

require 'ripper'
require 'test/unit'

class TestRipper_ScannerEvents < Test::Unit::TestCase

  class R < Ripper
    def R.scan(target, src)
      new(src, target).parse
    end

    def initialize(src, target)
      super src
      @target = target ? ('on__' + target).intern : nil
    end

    def parse
      @tokens = []
      super
      @tokens.sort_by {|tok,pos| pos }.map {|tok,| tok }
    end

    def on__scan(type, tok)
      @tokens.push [tok,[lineno(),column()]] if !@target or type == @target
    end
  end

  class PosInfo < Ripper
    def parse
      @q = []
      super
      @q
    end

    def on__scan(type, tok)
      @q.push [tok, type, lineno(), column()]
    end
  end

  def test_scan
    assert_equal [],
                 R.scan(nil, '')
    assert_equal ['a'],
                 R.scan(nil, 'a')
    assert_equal ['1'],
                 R.scan(nil, '1')
    assert_equal ['1', ';', 'def', ' ', 'm', '(', 'arg', ')', 'end'],
                 R.scan(nil, "1;def m(arg)end")
    assert_equal ['print', '(', '<<EOS', ')', "\n", "heredoc\n", "EOS\n"],
                 R.scan(nil, "print(<<EOS)\nheredoc\nEOS\n")
    assert_equal ['print', '(', ' ', '<<EOS', ')', "\n", "heredoc\n", "EOS\n"],
                 R.scan(nil, "print( <<EOS)\nheredoc\nEOS\n")
  end

  def test_location
    validate_location ""
    validate_location " "
    validate_location "@"
    validate_location "\n"
    validate_location "\r\n"
    validate_location "\n\n\n\n\n\r\n\n\n"
    validate_location "\n;\n;\n;\n;\n"
    validate_location "nil"
    validate_location "@ivar"
    validate_location "1;2;3"
    validate_location "1\n2\n3"
    validate_location "1\n2\n3\n"
    validate_location "def m(a) nil end"
    validate_location "if true then false else nil end"
    validate_location "BEGIN{print nil}"
    validate_location "%w(a b\nc\r\nd \ne )"
    validate_location %Q["a\nb\r\nc"]
    validate_location "print(<<EOS)\nheredoc\nEOS\n"
    validate_location %Q[print(<<-"EOS")\nheredoc\n     EOS\n]
  end

  def validate_location(src)
    data = PosInfo.new(src).parse
    buf = ''
    data.sort_by {|tok, type, line, col| [line,col] }\
        .each do |tok, type, line, col|
      assert_equal buf.count("\n") + 1, line,
          "wrong lineno: #{tok.inspect} (#{type}) [#{line}:#{col}]"
      assert_equal buf.sub(/\A.*\n/m, '').size, col,
          "wrong column: #{tok.inspect} (#{type}) [#{line}:#{col}]"
      buf << tok
    end
    assert_equal src, buf
  end

  def test_backref
    assert_equal ["$`", "$&", "$'", '$1', '$2', '$3'],
                 R.scan('backref', %q[m($~, $`, $&, $', $1, $2, $3)])
  end

  def test_backtick
    assert_equal ["`"],
                 R.scan('backtick', %q[p `make all`])
  end

  def test_comma
    assert_equal [','] * 6,
                 R.scan('comma', %q[ m(0,1,2,3,4,5,6) ])
    assert_equal [],
                 R.scan('comma', %q[".,.,.,.,.,.,.."])
    assert_equal [],
                 R.scan('comma', %Q[<<EOS\n,,,,,,,,,,\nEOS])
  end

  def test_period
    assert_equal [],
                 R.scan('period', '')
    assert_equal ['.'],
                 R.scan('period', 'a.b')
    assert_equal ['.'],
                 R.scan('period', 'Object.new')
    assert_equal [],
                 R.scan('period', '"."')
    assert_equal [],
                 R.scan('period', '1..2')
    assert_equal [],
                 R.scan('period', '1...3')
  end

  def test_const
    assert_equal ['CONST'],
                 R.scan('const', 'CONST')
    assert_equal ['C'],
                 R.scan('const', 'C')
    assert_equal ['CONST_A'],
                 R.scan('const', 'CONST_A')
    assert_equal ['Const', 'Const2', 'Const3'],
                 R.scan('const', 'Const; Const2; Const3')
    assert_equal ['Const'],
                 R.scan('const', 'Const(a)')
    assert_equal ['M', 'A', 'A2'],
                 R.scan('const', 'M(A,A2)')
    assert_equal [],
                 R.scan('const', '')
    assert_equal [],
                 R.scan('const', 'm(lvar, @ivar, @@cvar, $gvar)')
  end

  def test_cvar
    assert_equal [],
                 R.scan('cvar', '')
    assert_equal ['@@cvar'],
                 R.scan('cvar', '@@cvar')
    assert_equal ['@@__cvar__'],
                 R.scan('cvar', '@@__cvar__')
    assert_equal ['@@CVAR'],
                 R.scan('cvar', '@@CVAR')
    assert_equal ['@@cvar'],
                 R.scan('cvar', '   @@cvar#comment')
    assert_equal ['@@cvar'],
                 R.scan('cvar', ':@@cvar')
    assert_equal ['@@cvar'],
                 R.scan('cvar', 'm(lvar, @ivar, @@cvar, $gvar)')
    assert_equal [],
                 R.scan('cvar', '"@@cvar"')
  end

  def test_embexpr_beg
    assert_equal [],
                 R.scan('embexpr_beg', '')
    assert_equal ['#{'],
                 R.scan('embexpr_beg', '"#{expr}"')
    assert_equal [],
                 R.scan('embexpr_beg', '%q[#{expr}]')
    assert_equal ['#{'],
                 R.scan('embexpr_beg', '%Q[#{expr}]')
    assert_equal ['#{'],
                 R.scan('embexpr_beg', "m(<<EOS)\n\#{expr}\nEOS")
  end

=begin
  def test_embexpr_end
    assert_equal [],
                 R.scan('embexpr_end', '')
    assert_equal ['}'],
                 R.scan('embexpr_end', '"#{expr}"')
    assert_equal [],
                 R.scan('embexpr_end', '%q[#{expr}]')
    assert_equal ['}'],
                 R.scan('embexpr_end', '%Q[#{expr}]')
    assert_equal ['}'],
                 R.scan('embexpr_end', "m(<<EOS)\n\#{expr}\nEOS")
  end
=end

  def test_embvar
    assert_equal [],
                 R.scan('embvar', '')
    assert_equal ['#'],
                 R.scan('embvar', '"#$gvar"')
    assert_equal ['#'],
                 R.scan('embvar', '"#@ivar"')
    assert_equal ['#'],
                 R.scan('embvar', '"#@@cvar"')
    assert_equal [],
                 R.scan('embvar', '"#lvar"')
    assert_equal [],
                 R.scan('embvar', '"#"')
    assert_equal [],
                 R.scan('embvar', '"\#$gvar"')
    assert_equal [],
                 R.scan('embvar', '"\#@ivar"')
    assert_equal [],
                 R.scan('embvar', '%q[#@ivar]')
    assert_equal ['#'],
                 R.scan('embvar', '%Q[#@ivar]')
  end

  def test_float
    assert_equal [],
                 R.scan('float', '')
    assert_equal ['1.000'],
                 R.scan('float', '1.000')
    assert_equal ['123.456'],
                 R.scan('float', '123.456')
    assert_equal ['1.2345678901234567890123456789'],
                 R.scan('float', '1.2345678901234567890123456789')
    assert_equal ['1.000'],
                 R.scan('float', '   1.000# comment')
    assert_equal ['1.234e5'],
                 R.scan('float', '1.234e5')
    assert_equal ['1.234e1234567890'],
                 R.scan('float', '1.234e1234567890')
    assert_equal ['1.0'],
                 R.scan('float', 'm(a,b,1.0,c,d)')
  end

  def test_gvar
    assert_equal [],
                 R.scan('gvar', '')
    assert_equal ['$a'],
                 R.scan('gvar', '$a')
    assert_equal ['$A'],
                 R.scan('gvar', '$A')
    assert_equal ['$gvar'],
                 R.scan('gvar', 'm(lvar, @ivar, @@cvar, $gvar)')
    assert_equal %w($_ $~ $* $$ $? $! $@ $/ $\\ $; $, $. $= $: $< $> $"),
                 R.scan('gvar', 'm($_, $~, $*, $$, $?, $!, $@, $/, $\\, $;, $,, $., $=, $:, $<, $>, $")')
  end

  def test_ident
    assert_equal [],
                 R.scan('ident', '')
    assert_equal ['lvar'],
                 R.scan('ident', 'lvar')
    assert_equal ['m', 'lvar'],
                 R.scan('ident', 'm(lvar, @ivar, @@cvar, $gvar)')
  end

  def test_int
    assert_equal [],
                 R.scan('int', '')
    assert_equal ['1', '10', '100000000000000'],
                 R.scan('int', 'm(1,10,100000000000000)')
  end

  def test_ivar
    assert_equal [],
                 R.scan('ivar', '')
    assert_equal ['@ivar'],
                 R.scan('ivar', '@ivar')
    assert_equal ['@__ivar__'],
                 R.scan('ivar', '@__ivar__')
    assert_equal ['@IVAR'],
                 R.scan('ivar', '@IVAR')
    assert_equal ['@ivar'],
                 R.scan('ivar', 'm(lvar, @ivar, @@cvar, $gvar)')
  end

  def test_kw
    assert_equal [],
                 R.scan('kw', '')
    assert_equal %w(not),
                 R.scan('kw', 'not 1')
    assert_equal %w(and),
                 R.scan('kw', '1 and 2')
    assert_equal %w(or),
                 R.scan('kw', '1 or 2')
    assert_equal %w(if then else end),
                 R.scan('kw', 'if 1 then 2 else 3 end')
    assert_equal %w(if then elsif else end),
                 R.scan('kw', 'if 1 then 2 elsif 3 else 4 end')
    assert_equal %w(unless then end),
                 R.scan('kw', 'unless 1 then end')
    assert_equal %w(if true),
                 R.scan('kw', '1 if true')
    assert_equal %w(unless false),
                 R.scan('kw', '2 unless false')
    assert_equal %w(case when when else end),
                 R.scan('kw', 'case n; when 1; when 2; else 3 end')
    assert_equal %w(while do nil end),
                 R.scan('kw', 'while 1 do nil end')
    assert_equal %w(until do nil end),
                 R.scan('kw', 'until 1 do nil end')
    assert_equal %w(while),
                 R.scan('kw', '1 while 2')
    assert_equal %w(until),
                 R.scan('kw', '1 until 2')
    assert_equal %w(while break next retry end),
                 R.scan('kw', 'while 1; break; next; retry end')
    assert_equal %w(for in next break end),
                 R.scan('kw', 'for x in obj; next 1; break 2 end')
    assert_equal %w(begin rescue retry end),
                 R.scan('kw', 'begin 1; rescue; retry; end')
    assert_equal %w(rescue),
                 R.scan('kw', '1 rescue 2')
    assert_equal %w(def redo return end),
                 R.scan('kw', 'def m() redo; return end')
    assert_equal %w(def yield yield end),
                 R.scan('kw', 'def m() yield; yield 1 end')
    assert_equal %w(def super super super end),
                 R.scan('kw', 'def m() super; super(); super(1) end')
    assert_equal %w(alias),
                 R.scan('kw', 'alias a b')
    assert_equal %w(undef),
                 R.scan('kw', 'undef public')
    assert_equal %w(class end),
                 R.scan('kw', 'class A < Object; end')
    assert_equal %w(module end),
                 R.scan('kw', 'module M; end')
    assert_equal %w(class end),
                 R.scan('kw', 'class << obj; end')
    assert_equal %w(BEGIN),
                 R.scan('kw', 'BEGIN { }')
    assert_equal %w(END),
                 R.scan('kw', 'END { }')
    assert_equal %w(self),
                 R.scan('kw', 'self.class')
    assert_equal %w(nil true false),
                 R.scan('kw', 'p(nil, true, false)')
    assert_equal %w(__FILE__ __LINE__),
                 R.scan('kw', 'p __FILE__, __LINE__')
    assert_equal %w(defined?),
                 R.scan('kw', 'defined?(Object)')
  end

  def test_lbrace
    assert_equal [],
                 R.scan('lbrace', '')
    assert_equal ['{'],
                 R.scan('lbrace', '3.times{ }')
    assert_equal ['{'],
                 R.scan('lbrace', '3.times  { }')
    assert_equal ['{'],
                 R.scan('lbrace', '3.times{}')
    assert_equal [],
                 R.scan('lbrace', '"{}"')
    assert_equal ['{'],
                 R.scan('lbrace', '{1=>2}')
  end

  def test_rbrace
    assert_equal [],
                 R.scan('rbrace', '')
    assert_equal ['}'],
                 R.scan('rbrace', '3.times{ }')
    assert_equal ['}'],
                 R.scan('rbrace', '3.times  { }')
    assert_equal ['}'],
                 R.scan('rbrace', '3.times{}')
    assert_equal [],
                 R.scan('rbrace', '"{}"')
    assert_equal ['}'],
                 R.scan('rbrace', '{1=>2}')
  end

  def test_lbracket
    assert_equal [],
                 R.scan('lbracket', '')
    assert_equal ['['],
                 R.scan('lbracket', '[]')
    assert_equal ['['],
                 R.scan('lbracket', 'a[1]')
    assert_equal [],
                 R.scan('lbracket', 'm(%q[])')
  end

  def test_rbracket
    assert_equal [],
                 R.scan('rbracket', '')
    assert_equal [']'],
                 R.scan('rbracket', '[]')
    assert_equal [']'],
                 R.scan('rbracket', 'a[1]')
    assert_equal [],
                 R.scan('rbracket', 'm(%q[])')
  end

  def test_lparen
    assert_equal [],
                 R.scan('lparen', '')
    assert_equal ['('],
                 R.scan('lparen', '()')
    assert_equal ['('],
                 R.scan('lparen', 'm()')
    assert_equal ['('],
                 R.scan('lparen', 'm (a)')
    assert_equal [],
                 R.scan('lparen', '"()"')
    assert_equal [],
                 R.scan('lparen', '"%w()"')
  end

  def test_rparen
    assert_equal [],
                 R.scan('rparen', '')
    assert_equal [')'],
                 R.scan('rparen', '()')
    assert_equal [')'],
                 R.scan('rparen', 'm()')
    assert_equal [')'],
                 R.scan('rparen', 'm (a)')
    assert_equal [],
                 R.scan('rparen', '"()"')
    assert_equal [],
                 R.scan('rparen', '"%w()"')
  end

  def test_op
    assert_equal [],
                 R.scan('op', '')
    assert_equal ['|'],
                 R.scan('op', '1 | 1')
    assert_equal ['^'],
                 R.scan('op', '1 ^ 1')
    assert_equal ['&'],
                 R.scan('op', '1 & 1')
    assert_equal ['<=>'],
                 R.scan('op', '1 <=> 1')
    assert_equal ['=='],
                 R.scan('op', '1 == 1')
    assert_equal ['==='],
                 R.scan('op', '1 === 1')
    assert_equal ['=~'],
                 R.scan('op', '1 =~ 1')
    assert_equal ['>'],
                 R.scan('op', '1 > 1')
    assert_equal ['>='],
                 R.scan('op', '1 >= 1')
    assert_equal ['<'],
                 R.scan('op', '1 < 1')
    assert_equal ['<='],
                 R.scan('op', '1 <= 1')
    assert_equal ['<<'],
                 R.scan('op', '1 << 1')
    assert_equal ['>>'],
                 R.scan('op', '1 >> 1')
    assert_equal ['+'],
                 R.scan('op', '1 + 1')
    assert_equal ['-'],
                 R.scan('op', '1 - 1')
    assert_equal ['*'],
                 R.scan('op', '1 * 1')
    assert_equal ['/'],
                 R.scan('op', '1 / 1')
    assert_equal ['%'],
                 R.scan('op', '1 % 1')
    assert_equal ['**'],
                 R.scan('op', '1 ** 1')
    assert_equal ['~'],
                 R.scan('op', '~1')
    assert_equal ['-'],
                 R.scan('op', '-a')
    assert_equal ['+'],
                 R.scan('op', '+a')
    assert_equal ['[]'],
                 R.scan('op', ':[]')
    assert_equal ['[]='],
                 R.scan('op', ':[]=')
    assert_equal [],
                 R.scan('op', %q[`make all`])
  end

  def test_symbeg
    assert_equal [],
                 R.scan('symbeg', '')
    assert_equal [':'],
                 R.scan('symbeg', ':sym')
    assert_equal [':'],
                 R.scan('symbeg', '[1,2,3,:sym]')
    assert_equal [],
                 R.scan('symbeg', '":sym"')
    assert_equal [],
                 R.scan('symbeg', 'a ? b : c')
  end

  def test_tstring_beg
    assert_equal [],
                 R.scan('tstring_beg', '')
    assert_equal ['"'],
                 R.scan('tstring_beg', '"abcdef"')
    assert_equal ['%q['],
                 R.scan('tstring_beg', '%q[abcdef]')
    assert_equal ['%Q['],
                 R.scan('tstring_beg', '%Q[abcdef]')
  end

  def test_tstring_content
    assert_equal [],
                 R.scan('tstring_content', '')
    assert_equal ['abcdef'],
                 R.scan('tstring_content', '"abcdef"')
    assert_equal ['abcdef'],
                 R.scan('tstring_content', '%q[abcdef]')
    assert_equal ['abcdef'],
                 R.scan('tstring_content', '%Q[abcdef]')
    assert_equal ['abc', 'def'],
                 R.scan('tstring_content', '"abc#{1}def"')
    assert_equal ['sym'],
                 R.scan('tstring_content', ':"sym"')
  end

  def test_tstring_end
    assert_equal [],
                 R.scan('tstring_end', '')
    assert_equal ['"'],
                 R.scan('tstring_end', '"abcdef"')
    assert_equal [']'],
                 R.scan('tstring_end', '%q[abcdef]')
    assert_equal [']'],
                 R.scan('tstring_end', '%Q[abcdef]')
  end

  def test_regexp_beg
    assert_equal [],
                 R.scan('regexp_beg', '')
    assert_equal ['/'],
                 R.scan('regexp_beg', '/re/')
    assert_equal ['%r<'],
                 R.scan('regexp_beg', '%r<re>')
    assert_equal [],
                 R.scan('regexp_beg', '5 / 5')
  end

  def test_regexp_end
    assert_equal [],
                 R.scan('regexp_end', '')
    assert_equal ['/'],
                 R.scan('regexp_end', '/re/')
    assert_equal ['>'],
                 R.scan('regexp_end', '%r<re>')
  end

  def test_words_beg
    assert_equal [],
                 R.scan('words_beg', '')
    assert_equal ['%W('],
                 R.scan('words_beg', '%W()')
    assert_equal ['%W('],
                 R.scan('words_beg', '%W(w w w)')
    assert_equal ['%W( '],
                 R.scan('words_beg', '%W( w w w )')
  end

  def test_qwords_beg
    assert_equal [],
                 R.scan('qwords_beg', '')
    assert_equal ['%w('],
                 R.scan('qwords_beg', '%w()')
    assert_equal ['%w('],
                 R.scan('qwords_beg', '%w(w w w)')
    assert_equal ['%w( '],
                 R.scan('qwords_beg', '%w( w w w )')
  end

  # FIXME: Close paren must not present (`words_end' scanner event?).
  def test_words_sep
    assert_equal [],
                 R.scan('words_sep', '')
    assert_equal [')'],
                 R.scan('words_sep', '%w()')
    assert_equal [' ', ' ', ')'],
                 R.scan('words_sep', '%w(w w w)')
    assert_equal [' ', ' ', ' )'],
                 R.scan('words_sep', '%w( w w w )')
    assert_equal ["\n", ' ', ' )'],
                 R.scan('words_sep', "%w( w\nw w )")
  end

  def test_heredoc_beg
    assert_equal [],
                 R.scan('heredoc_beg', '')
    assert_equal ['<<EOS'],
                 R.scan('heredoc_beg', "<<EOS\nheredoc\nEOS")
    assert_equal ['<<EOS'],
                 R.scan('heredoc_beg', "<<EOS\nheredoc\nEOS\n")
    assert_equal ['<<EOS'],
                 R.scan('heredoc_beg', "<<EOS\nheredoc\nEOS \n")
    assert_equal ['<<-EOS'],
                 R.scan('heredoc_beg', "<<-EOS\nheredoc\n\tEOS \n")
    assert_equal ['<<"EOS"'],
                 R.scan('heredoc_beg', %Q[<<"EOS"\nheredoc\nEOS])
    assert_equal [%q(<<'EOS')],
                 R.scan('heredoc_beg', "<<'EOS'\nheredoc\nEOS")
    assert_equal [%q(<<`EOS`)],
                 R.scan('heredoc_beg', "<<`EOS`\nheredoc\nEOS")
    assert_equal [%q(<<" ")],
                 R.scan('heredoc_beg', %Q[<<" "\nheredoc\nEOS])
  end

  def test_tstring_content_HEREDOC
    assert_equal [],
                 R.scan('tstring_content', '')
    assert_equal ["heredoc\n"],
                 R.scan('tstring_content', "<<EOS\nheredoc\nEOS")
    assert_equal ["heredoc\n"],
                 R.scan('tstring_content', "<<EOS\nheredoc\nEOS\n")
    assert_equal ["heredoc \n"],
                 R.scan('tstring_content', "<<EOS\nheredoc \nEOS \n")
    assert_equal ["heredoc\n"],
                 R.scan('tstring_content', "<<-EOS\nheredoc\n\tEOS \n")
  end

  def test_heredoc_end
    assert_equal [],
                 R.scan('heredoc_end', '')
    assert_equal ["EOS"],
                 R.scan('heredoc_end', "<<EOS\nheredoc\nEOS")
    assert_equal ["EOS\n"],
                 R.scan('heredoc_end', "<<EOS\nheredoc\nEOS\n")
    assert_equal ["EOS \n"],
                 R.scan('heredoc_end', "<<EOS\nheredoc\nEOS \n")
    assert_equal ["\tEOS \n"],
                 R.scan('heredoc_end', "<<-EOS\nheredoc\n\tEOS \n")
  end

  def test_semicolon
    assert_equal [],
                 R.scan('semicolon', '')
    assert_equal %w(;),
                 R.scan('semicolon', ';')
    assert_equal %w(; ;),
                 R.scan('semicolon', ';;')
    assert_equal %w(; ; ;),
                 R.scan('semicolon', 'nil;nil;nil;')
    assert_equal %w(; ; ;),
                 R.scan('semicolon', 'nil;nil;nil;nil')
    assert_equal [],
                 R.scan('semicolon', '";"')
    assert_equal [],
                 R.scan('semicolon', '%w(;)')
    assert_equal [],
                 R.scan('semicolon', '/;/')
  end

  def test_comment
    assert_equal [],
                 R.scan('comment', '')
    assert_equal ['# comment'],
                 R.scan('comment', '# comment')
    assert_equal ["# comment\n"],
                 R.scan('comment', "# comment\n")
    assert_equal ["# comment\n"],
                 R.scan('comment', "# comment\n1 + 1")
    assert_equal ["# comment\n"],
                 R.scan('comment', "1 + 1 + 1# comment\n1 + 1")
  end

  def test_embdoc_beg
    assert_equal [],
                 R.scan('embdoc_beg', '')
    assert_equal ["=begin\n"],
                 R.scan('embdoc_beg', "=begin\ndoc\n=end")
    assert_equal ["=begin \n"],
                 R.scan('embdoc_beg', "=begin \ndoc\n=end\n")
    assert_equal ["=begin comment\n"],
                 R.scan('embdoc_beg', "=begin comment\ndoc\n=end\n")
  end

  def test_embdoc
    assert_equal [],
                 R.scan('embdoc', '')
    assert_equal ["doc\n"],
                 R.scan('embdoc', "=begin\ndoc\n=end")
    assert_equal ["doc\n"],
                 R.scan('embdoc', "=begin\ndoc\n=end\n")
  end

  def test_embdoc_end
    assert_equal [],
                 R.scan('embdoc_end', '')
    assert_equal ["=end"],
                 R.scan('embdoc_end', "=begin\ndoc\n=end")
    assert_equal ["=end\n"],
                 R.scan('embdoc_end', "=begin\ndoc\n=end\n")
  end

  def test_sp
    assert_equal [],
                 R.scan('sp', '')
    assert_equal [' '],
                 R.scan('sp', ' ')
    assert_equal [' '],
                 R.scan('sp', ' 1')
    assert_equal [],
                 R.scan('sp', "\n")
    assert_equal [' '],
                 R.scan('sp', " \n")
    assert_equal [' ', ' '],
                 R.scan('sp', "1 + 1")
    assert_equal [],
                 R.scan('sp', "' '")
    assert_equal [],
                 R.scan('sp', "%w(  )")
    assert_equal [],
                 R.scan('sp', "%w(  w  )")
    assert_equal [],
                 R.scan('sp', "p(/ /)")
  end

  # `nl' event always means End-Of-Statement.
  def test_nl
    assert_equal [],
                 R.scan('nl', '')
    assert_equal [],
                 R.scan('nl', "\n")
    assert_equal ["\n"],
                 R.scan('nl', "1 + 1\n")
    assert_equal ["\n", "\n"],
                 R.scan('nl', "1 + 1\n2 + 2\n")
    assert_equal [],
                 R.scan('nl', "1 +\n1")
    assert_equal [],
                 R.scan('nl', "1;\n")
    assert_equal ["\r\n"],
                 R.scan('nl', "1 + 1\r\n")
    assert_equal [],
                 R.scan('nl', "1;\r\n")
  end

  def test_ignored_nl
    assert_equal [],
                 R.scan('ignored_nl', '')
    assert_equal ["\n"],
                 R.scan('ignored_nl', "\n")
    assert_equal [],
                 R.scan('ignored_nl', "1 + 1\n")
    assert_equal [],
                 R.scan('ignored_nl', "1 + 1\n2 + 2\n")
    assert_equal ["\n"],
                 R.scan('ignored_nl', "1 +\n1")
    assert_equal ["\n"],
                 R.scan('ignored_nl', "1;\n")
    assert_equal [],
                 R.scan('ignored_nl', "1 + 1\r\n")
    assert_equal ["\r\n"],
                 R.scan('ignored_nl', "1;\r\n")
  end

  def test___end__
    assert_equal [],
                 R.scan('__end__', "")
    assert_equal ["__END__"],
                 R.scan('__end__', "__END__")
    assert_equal ["__END__\n"],
                 R.scan('__end__', "__END__\n")
    assert_equal ["__END__\n"],
                 R.scan(nil, "__END__\njunk junk junk")
    assert_equal ["__END__"],
                 R.scan('__end__', "1\n__END__")
    assert_equal [],
                 R.scan('__end__', "print('__END__')")
  end

  def test_CHAR
    assert_equal [],
                 R.scan('CHAR', "")
    assert_equal ["@"],
                 R.scan('CHAR', "@")
    assert_equal [],
                 R.scan('CHAR', "@ivar")
  end

end
