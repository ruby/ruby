#
#               Date.rb - 
#                       $Release Version: $
#                       $Revision: 1.1.1.1 $
#                       $Date: 1998/01/16 04:05:49 $
#                       by Yasuo OHBA(SHL Japan Inc. Technology Dept.)
#
# --
#
#    September 1752
#  S  M Tu  W Th  F  S
#        1  2 14 15 16
# 17 18 19 20 21 22 23
# 24 25 26 27 28 29 30
#       

class Date
  include Comparable
  
  def initialize(y = 1, m = 1, d = 1)
    if y.kind_of?(String) && y.size == 8
      @year = y[0,4].to_i
      @month = y[4,2].to_i
      @day = y[6,2].to_i
    else
      if m.kind_of?(String)
        ml = {"jan"=>1, "feb"=>2, "mar"=>3, "apr"=>4, "may"=>5, "jun"=>6, "jul"=>7, "aug"=>8, "sep"=>9, "oct"=>10, "nov"=>11, "dec"=>12}
        m = ml[m.downcase]
        if m.nil?
          raise ArgumentError, "Wrong argument. (month)"
        end
      end
      @year = y.to_i
      @month = m.to_i
      @day = d.to_i
    end
    _check_date
    return self
  end
  
  def year
    return @year
  end
  
  def month
    return @month
  end
  
  def day
    return @day
  end
  
  def period
    return Date.period!(@year, @month, @day)
  end
  
  def day_of_week
    dl = Date.daylist(@year)
    d = Date.jan1!(@year)
    for m in 1..(@month - 1)
      d += dl[m]
    end
    d += @day - 1
    if @year == 1752 && @month == 9 && @day >= 14
      d -= (14 - 3)
    end
    return (d % 7)
  end
  
  Weektag = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
  def name_of_week
    return Weektag[self.day_of_week]
  end
  
  def +(o)
    if o.kind_of?(Numeric)
      d = Integer(self.period + o)
    elsif o.kind_of?(Date)
      d = self.period + o.period
    else
      raise TypeError, "Illegal type. (Integer or Date)"
    end
    return Date.at(d)
  end
  
  def -(o)
    if o.kind_of?(Numeric)
      d = Integer(self.period - o)
    elsif o.kind_of?(Date)
      return Integer(self.period - o.period)
    else
      raise TypeError, "Illegal type. (Integer or Date)"
    end
    if d <= 0
      raise ArgumentError, "argument out of range. (self > other)"
    end
    return Date.at(d)
  end
  
  def <=>(o)
    if o.kind_of?(Integer)
      d = o
    elsif o.kind_of?(Date)
      d = o.period
    else
      raise TypeError, "Illegal type. (Integer or Date)"
    end
    return self.period <=> d
  end

  def eql?(o)
    self == o
  end
  
  def hash
    return @year ^ @month ^ @day
  end
  
  def leapyear?
    if Date.leapyear(@year) == 1
      return FALSE
    else
      return TRUE
    end
  end

  def _check_date
    m = Date.daylist(@year)
    if @month < 1 || @month > 12
      raise ArgumentError, "argument(month) out of range."
      return nil
    end
    if @year == 1752 && @month == 9
      if @day >= 3 && @day <= 13
        raise ArgumentError, "argument(1752/09/3-13) out of range."
        return nil
      end
      d = 30
    else
      d = m[@month]
    end
    if @day < 1 || @day > d
      raise ArgumentError, "argument(day) out of range."
      return nil
    end
    return self
  end
  
  private :_check_date
end

def Date.at(d)
  if d.kind_of? Time
    return Date.new(1900+d.year, d.mon+1, d.mday)
  end
  if d.kind_of? Date
    return Date.at(d.period)
  end
  mm = 1
  yy = (d / 366.0).to_i
  if yy != 0
    dd = d - (Date.period!(yy, 1, 1) - 1)
  else
    dd = d
    yy = 1
  end
  dl = Date.daylist(yy)
  while dd > dl[mm]
    if dd > dl[0]
      dd -= dl[0]
      yy += 1
      dl = Date.daylist(yy)
    else
      dd -= dl[mm]
      mm += 1
    end
  end
  if yy == 1752 && mm == 9 && dd >= 3 && dd <= 19
    dd += (14 - 3)              # 1752/09/03-19 -> 1752/09/14-30
  end
  
  return Date.new(yy, mm, dd)
end

def Date.period!(y, m, d)
  p = d
  dl = Date.daylist(y)
  for mm in 1..(m - 1)
    p += dl[mm]
  end
  p += (y - 1) * 365 + ((y - 1) / 4.0).to_i
  if (y - 1) > 1752
    p -= ((y - 1 - 1752) / 100.0).to_i
    p += ((y - 1 - 1752) / 400.0).to_i
    p -= (14 - 3)
  elsif y == 1752 && m == 9 && d >= 14 && d <= 30
    p -= (14 - 3)
  end
  return p
end

def Date.leapyear(yy)
  return ((Date.jan1!(yy + 1) + 7 - Date.jan1!(yy)) % 7)
end

def Date.daylist(yy)
  case (Date.leapyear(yy))
  when 1 # non-leapyear
    return [365, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  when 2 # leapyear
    return [366, 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  else   # 1752
    return [355, 31, 29, 31, 30, 31, 30, 31, 31, 19, 31, 30, 31]
  end
end

def Date.jan1!(y)
  d = 4 + y + (y + 3) / 4
  if y > 1800
    d -= (y - 1701) / 100
    d += (y - 1601) / 400
  end
  if y > 1752
    d += 3
  end
  return (d % 7)
end
