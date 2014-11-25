#--
# Extensions to time to allow comparisons with early and late time classes.

require 'rake/early_time'
require 'rake/late_time'

class Time # :nodoc: all
  alias rake_original_time_compare :<=>
  def <=>(other)
    if Rake::EarlyTime === other || Rake::LateTime === other
      - other.<=>(self)
    else
      rake_original_time_compare(other)
    end
  end
end
