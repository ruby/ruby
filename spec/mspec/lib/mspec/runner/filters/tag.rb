class TagFilter
  def initialize(what, *tags)
    @what = what
    @tags = tags
  end

  def load
    @descriptions = MSpec.read_tags(@tags).map { |t| t.description }
    MSpec.register @what, self
  end

  def unload
    MSpec.unregister @what, self
  end

  def ===(string)
    @descriptions.include?(string)
  end

  def register
    MSpec.register :load, self
    MSpec.register :unload, self
  end

  def unregister
    MSpec.unregister :load, self
    MSpec.unregister :unload, self
  end
end
