class RegexpFilter
  def initialize(what, *regexps)
    @what = what
    @regexps = to_regexp(*regexps)
  end

  def ===(string)
    @regexps.any? { |regexp| regexp === string }
  end

  def register
    MSpec.register @what, self
  end

  def unregister
    MSpec.unregister @what, self
  end

  def to_regexp(*regexps)
    regexps.map { |str| Regexp.new str }
  end
  private :to_regexp
end
