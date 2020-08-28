class SpecVersion
  # If beginning implementations have a problem with this include, we can
  # manually implement the relational operators that are needed.
  include Comparable

  # SpecVersion handles comparison correctly for the context by filling in
  # missing version parts according to the value of +ceil+. If +ceil+ is
  # +false+, 0 digits fill in missing version parts. If +ceil+ is +true+, 9
  # digits fill in missing parts. (See e.g. VersionGuard and BugGuard.)
  def initialize(version, ceil = false)
    @version = version
    @ceil    = ceil
    @integer = nil
  end

  def to_s
    @version
  end

  def to_str
    to_s
  end

  # Converts a string representation of a version major.minor.tiny
  # to an integer representation so that comparisons can be made. For example,
  # "2.2.10" < "2.2.2" would be false if compared as strings.
  def to_i
    unless @integer
      major, minor, tiny = @version.split "."
      if @ceil
        tiny = 99 unless tiny
      end
      parts = [major, minor, tiny].map { |x| x.to_i }
      @integer = ("1%02d%02d%02d" % parts).to_i
    end
    @integer
  end

  def to_int
    to_i
  end

  def <=>(other)
    if other.respond_to? :to_int
      other = Integer(other.to_int)
    else
      other = SpecVersion.new(String(other)).to_i
    end

    self.to_i <=> other
  end
end
