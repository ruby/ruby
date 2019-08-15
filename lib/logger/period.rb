class Logger
  module Period
    module_function

    SiD = 24 * 60 * 60

    def next_rotate_time(now, shift_age)
      case shift_age
      when 'daily'
        t = Time.mktime(now.year, now.month, now.mday) + SiD
      when 'weekly'
        t = Time.mktime(now.year, now.month, now.mday) + SiD * (7 - now.wday)
      when 'monthly'
        t = Time.mktime(now.year, now.month, 1) + SiD * 32
        return Time.mktime(t.year, t.month, 1)
      else
        return now
      end
      if t.hour.nonzero? or t.min.nonzero? or t.sec.nonzero?
        hour = t.hour
        t = Time.mktime(t.year, t.month, t.mday)
        t += SiD if hour > 12
      end
      t
    end

    def previous_period_end(now, shift_age)
      case shift_age
      when 'daily'
        t = Time.mktime(now.year, now.month, now.mday) - SiD / 2
      when 'weekly'
        t = Time.mktime(now.year, now.month, now.mday) - (SiD * now.wday + SiD / 2)
      when 'monthly'
        t = Time.mktime(now.year, now.month, 1) - SiD / 2
      else
        return now
      end
      Time.mktime(t.year, t.month, t.mday, 23, 59, 59)
    end
  end
end
