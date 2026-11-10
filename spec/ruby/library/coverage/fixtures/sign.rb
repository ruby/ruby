module CoverageSpecs
  def self.sign(x)
    x < 0 ? :negative : :positive
  end
end
