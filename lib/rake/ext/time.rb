#--
# Extensions to time to allow comparisons with an early time class.

require 'rake/early_time'

class Time # :nodoc: all
  alias rake_original_time_compare :<=>
  def <=>(other)
    if Rake::EarlyTime === other
      - other.<=>(self)
    else
      rake_original_time_compare(other)
    end
  end
end
