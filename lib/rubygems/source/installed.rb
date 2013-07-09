class Gem::Source::Installed < Gem::Source

  def initialize
  end

  ##
  # Installed sources sort before all other sources

  def <=> other
    case other
    when Gem::Source::Installed then
      0
    when Gem::Source then
      1
    else
      nil
    end
  end

  ##
  # We don't need to download an installed gem

  def download spec, path
    nil
  end

end

