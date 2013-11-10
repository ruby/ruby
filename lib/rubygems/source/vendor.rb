##
# This represents a vendored source that is similar to an installed gem.

class Gem::Source::Vendor < Gem::Source::Installed

  def initialize uri
    @uri = uri
  end

end

