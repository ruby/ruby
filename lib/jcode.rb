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
    if $KCODE =~ /^s/i
      self =~ /[\x81-\x9f\xe0-\xef][\x40-\x7e\x80-\xfc]/n
    elsif $KCODE =~ /^e/i
      self =~ /[\xa1-\xfe][\xa1-\xfe]/n
    else
      false
    end
  end

  def succ
    if self[-2] && self[-2] & 0x80 != 0
      s = self.dup
      s[-1] += 1
      s[-1] += 1 if !s.mbchar?
      return s
    else
      original_succ
    end
  end
  alias next succ

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

  def _expand_ch
    a = []
    self.scan(/(.|\n)-(.|\n)|(.|\n)/) do |r|
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

  def tr!(from, to)
    return self.delete!(from) if to.length == 0

    if from =~ /^\^/
      comp=TRUE
      from = $'
    end
    afrom = from._expand_ch
    ato = to._expand_ch
    i = 0
    if comp
      self.gsub!(/(.|\n)/) do |c|
	unless afrom.include?(c)
	  ato[-1]
	else
	  c
	end
      end
    else
      self.gsub!(/(.|\n)/) do |c|
	if i = afrom.index(c)
	  if i < ato.size then ato[i] else ato[-1] end
	else
	  c
	end
      end
    end
  end

  def tr(from, to)
    (str = self.dup).tr!(from, to) or str
  end

  def delete!(del)
    if del =~ /^\^/
      comp=TRUE
      del = $'
    end
    adel = del._expand_ch
    if comp
      self.gsub!(/(.|\n)/) do |c|
	next unless adel.include?(c)
	c
      end
    else
      self.gsub!(/(.|\n)/) do |c|
	next if adel.include?(c)
	c
      end
    end
  end

  def delete(del)
    (str = self.dup).delete!(del) or str
  end

  def squeeze!(del=nil)
    if del
      if del =~ /^\^/
	comp=TRUE
	del = $'
      end
      adel = del._expand_ch
      if comp
	self.gsub!(/(.|\n)\1+/) do
	  next unless adel.include?($1)
	  $&
	end
      else
	for c in adel
	  cq = Regexp.quote(c)
	  self.gsub!(/#{cq}(#{cq})+/, cq)
	end
      end
      self
    else
      self.gsub!(/(.|\n)\1+/, '\1')
    end
  end

  def squeeze(del=nil)
    (str = self.dup).squeeze!(del) or str
  end

  def tr_s!(from, to)
    return self.delete!(from) if to.length == 0
    if from =~ /^\^/
      comp=TRUE
      from = $'
    end
    afrom = from._expand_ch
    ato = to._expand_ch
    i = 0
    c = nil
    last = nil
    self.gsub!(/(.|\n)/) do |c|
      if comp
	unless afrom.include?(c)
	  c = ato[-1]
	  next if c == last
	  last = c
	else
	  last = nil
	  c
	end
      elsif i = afrom.index(c)
	c = if i < ato.size then ato[i] else ato[-1] end
	next if c == last
	last = c
      else
	last = nil
        c
      end
    end
  end

  def tr_s(from, to)
    (str = self.dup).tr_s!(from,to) or str
  end

  alias original_chop! chop!
  private :original_chop!

  def chop!
    if self =~ /(.)$/ and $1.size == 2
      original_chop!
    end
    original_chop!
  end

  def chop
    (str = self.dup).chop! or str
  end
end
$VERBOSE = $vsave
