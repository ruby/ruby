# jcode.rb - ruby code to handle japanese (EUC/SJIS) string

$vsave, $VERBOSE = $VERBOSE, FALSE
class String
  printf STDERR, "feel free for some warnings:\n" if $VERBOSE

  def jlength
    self.split(//).length
  end

  alias original_succ succ
  private :original_succ

  def mbchar?
    case $KCODE[0]
    when ?s, ?S
      self =~ /[\x81-\x9f\xe0-\xef][\x40-\x7e\x80-\xfc]/n
    when ?e, ?E
      self =~ /[\xa1-\xfe][\xa1-\xfe]/n
    else
      false
    end
  end

  def succ
    if self[-2] and self[-2, 2].mbchar?
      s = self.dup
      s[-1] += 1
      s[-1] += 1 unless s[-2, 2].mbchar?
      return s
    else
      original_succ
    end
  end

  def upto(to)
    return if self > to

    curr = self
    tail = self[-2..-1]
    if tail.length == 2 and tail  =~ /^.$/ then
      if self[0..-2] == to[0..-2]
	first = self[-2].chr
	for c in self[-1] .. to[-1]
	  if (first+c.chr).mbchar?
	    yield self[0..-2]+c.chr
	  end
	end
      end
    else
      loop do
	yield curr
	return if curr == to
	curr = curr.succ
	return if curr.length > to.length
      end
    end
    return nil
  end

  private

  def _expand_ch str
    a = []
    str.scan(/(.|\n)-(.|\n)|(.|\n)/) do |r|
      if $3
	a.push $3
      elsif $1.length != $2.length
 	next
      elsif $1.length == 1
 	$1[0].upto($2[0]) { |c| a.push c.chr }
      else
 	$1.upto($2) { |c| a.push c }
      end
    end
    a
  end

  HashCache = {}

  def expand_ch_hash from, to = ""
    key = from.intern.to_s + ":" + to.intern.to_s
    return HashCache[key] if HashCache.key? key
    afrom = _expand_ch(from)
    h = {}
    if to.length != 0
      ato = _expand_ch(to)
      afrom.each_with_index do |x,i| h[x] = ato[i] || ato[-1] end
    else
      afrom.each do |x| h[x] = true end
    end
    HashCache[key] = h
  end

  def bsquote(str)
    str.gsub(/\\/, '\\\\\\\\')
  end

  public

  def tr!(from, to)
    return self.delete!(from) if to.length == 0

    pattern = /[#{bsquote(from)}]/
    if from[0] == ?^
      last = /.$/.match(to)[0]
      self.gsub!(pattern, last)
    else
      h = expand_ch_hash(from, to)
      self.gsub!(pattern) do |c| h[c] end
    end
  end

  def tr(from, to)
    (str = self.dup).tr!(from, to) or str
  end

  def delete!(del)
    pattern = /[#{bsquote(del)}]+/
    self.gsub!(pattern, '')
  end

  def delete(del)
    (str = self.dup).delete!(del) or str
  end

  def squeeze!(del=nil)
    pattern =
      if del
        /([#{bsquote(del)}])\1+/
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

    pattern = /([#{bsquote(from)}])\1+/
    if from[0] == ?^
      last = /.$/.match(to)[0]
      self.gsub!(pattern, last)
    else
      h = expand_ch_hash(from, to)
      self.gsub!(pattern) do h[$1] end
    end
  end

  def tr_s(from, to)
    (str = self.dup).tr_s!(from,to) or str
  end

  def chop!
    self.gsub!(/(?:.|\n)\z/, '')
  end

  def chop
    (str = self.dup).chop! or str
  end

  def jcount(str)
    self.delete("^#{str}").jlength
  end

end
$VERBOSE = $vsave
