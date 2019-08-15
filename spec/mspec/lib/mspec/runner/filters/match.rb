class MatchFilter
  def initialize(what, *strings)
    @what = what
    @strings = strings
  end

  def ===(string)
    @strings.any? { |s| string.include?(s) }
  end

  def register
    MSpec.register @what, self
  end

  def unregister
    MSpec.unregister @what, self
  end
end
