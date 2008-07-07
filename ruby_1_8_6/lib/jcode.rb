# jcode.rb - ruby code to handle japanese (EUC/SJIS) string

if $VERBOSE && $KCODE == "NONE"
  warn "Warning: $KCODE is NONE."
end

$vsave, $VERBOSE = $VERBOSE, false
class String
  warn "feel free for some warnings:\n" if $VERBOSE

  def _regex_quote(str)
    str.gsub(/(\\[\[\]\-\\])|\\(.)|([\[\]\\])/) do
      $1 || $2 || '\\' + $3
    end
  end
  private :_regex_quote

  PATTERN_SJIS = '[\x81-\x9f\xe0-\xef][\x40-\x7e\x80-\xfc]'
  PATTERN_EUC = '[\xa1-\xfe][\xa1-\xfe]'
  PATTERN_UTF8 = '[\xc0-\xdf][\x80-\xbf]|[\xe0-\xef][\x80-\xbf][\x80-\xbf]'

  RE_SJIS = Regexp.new(PATTERN_SJIS, 0, 'n')
  RE_EUC = Regexp.new(PATTERN_EUC, 0, 'n')
  RE_UTF8 = Regexp.new(PATTERN_UTF8, 0, 'n')

  SUCC = {}
  SUCC['s'] = Hash.new(1)
  for i in 0 .. 0x3f
    SUCC['s'][i.chr] = 0x40 - i
  end
  SUCC['s']["\x7e"] = 0x80 - 0x7e
  SUCC['s']["\xfd"] = 0x100 - 0xfd
  SUCC['s']["\xfe"] = 0x100 - 0xfe
  SUCC['s']["\xff"] = 0x100 - 0xff
  SUCC['e'] = Hash.new(1)
  for i in 0 .. 0xa0
    SUCC['e'][i.chr] = 0xa1 - i
  end
  SUCC['e']["\xfe"] = 2
  SUCC['u'] = Hash.new(1)
  for i in 0 .. 0x7f
    SUCC['u'][i.chr] = 0x80 - i
  end
  SUCC['u']["\xbf"] = 0x100 - 0xbf

  def mbchar?
    case $KCODE[0]
    when ?s, ?S
      self =~ RE_SJIS
    when ?e, ?E
      self =~ RE_EUC
    when ?u, ?U
      self =~ RE_UTF8
    else
      nil
    end
  end

  def end_regexp
    case $KCODE[0]
    when ?s, ?S
      /#{PATTERN_SJIS}$/on
    when ?e, ?E
      /#{PATTERN_EUC}$/on
    when ?u, ?U
      /#{PATTERN_UTF8}$/on
    else
      /.$/on
    end
  end

  alias original_succ! succ!
  private :original_succ!

  alias original_succ succ
  private :original_succ

  def succ!
    reg = end_regexp
    if  $KCODE != 'NONE' && self =~ reg
      succ_table = SUCC[$KCODE[0,1].downcase]
      begin
	self[-1] += succ_table[self[-1]]
	self[-2] += 1 if self[-1] == 0
      end while self !~ reg
      self
    else
      original_succ!
    end
  end

  def succ
    str = self.dup
    str.succ! or str
  end

  private

  def _expand_ch str
    a = []
    str.scan(/(?:\\(.)|([^\\]))-(?:\\(.)|([^\\]))|(?:\\(.)|(.))/m) do
      from = $1 || $2
      to = $3 || $4
      one = $5 || $6
      if one
	a.push one
      elsif from.length != to.length
	next
      elsif from.length == 1
	from[0].upto(to[0]) { |c| a.push c.chr }
      else
	from.upto(to) { |c| a.push c }
      end
    end
    a
  end

  def expand_ch_hash from, to
    h = {}
    afrom = _expand_ch(from)
    ato = _expand_ch(to)
    afrom.each_with_index do |x,i| h[x] = ato[i] || ato[-1] end
    h
  end

  HashCache = {}
  TrPatternCache = {}
  DeletePatternCache = {}
  SqueezePatternCache = {}

  public

  def tr!(from, to)
    return nil if from == ""
    return self.delete!(from) if to == ""

    pattern = TrPatternCache[from] ||= /[#{_regex_quote(from)}]/
    if from[0] == ?^
      last = /.$/.match(to)[0]
      self.gsub!(pattern, last)
    else
      h = HashCache[from + "1-0" + to] ||= expand_ch_hash(from, to)
      self.gsub!(pattern) do |c| h[c] end
    end
  end

  def tr(from, to)
    (str = self.dup).tr!(from, to) or str
  end

  def delete!(del)
    return nil if del == ""
    self.gsub!(DeletePatternCache[del] ||= /[#{_regex_quote(del)}]+/, '')
  end

  def delete(del)
    (str = self.dup).delete!(del) or str
  end

  def squeeze!(del=nil)
    return nil if del == ""
    pattern =
      if del
	SqueezePatternCache[del] ||= /([#{_regex_quote(del)}])\1+/
      else
	/(.|\n)\1+/
      end
    self.gsub!(pattern, '\1')
  end

  def squeeze(del=nil)
    (str = self.dup).squeeze!(del) or str
  end

  def tr_s!(from, to)
    return self.delete!(from) if to.length == 0

    pattern = SqueezePatternCache[from] ||= /([#{_regex_quote(from)}])\1*/
    if from[0] == ?^
      last = /.$/.match(to)[0]
      self.gsub!(pattern, last)
    else
      h = HashCache[from + "1-0" + to] ||= expand_ch_hash(from, to)
      self.gsub!(pattern) do h[$1] end
    end
  end

  def tr_s(from, to)
    (str = self.dup).tr_s!(from,to) or str
  end

  def chop!
    self.gsub!(/(?:.|\r?\n)\z/, '')
  end

  def chop
    (str = self.dup).chop! or str
  end

  def jlength
    self.gsub(/[^\Wa-zA-Z_\d]/, ' ').length
  end
  alias jsize jlength

  def jcount(str)
    self.delete("^#{str}").jlength
  end

  def each_char
    if block_given?
      scan(/./m) do |x|
        yield x
      end
    else
      scan(/./m)
    end
  end

end
$VERBOSE = $vsave
