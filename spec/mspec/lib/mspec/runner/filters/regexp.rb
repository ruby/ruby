require 'mspec/runner/filters/match'

class RegexpFilter < MatchFilter
  def to_regexp(*strings)
    strings.map { |str| Regexp.new str }
  end
end
