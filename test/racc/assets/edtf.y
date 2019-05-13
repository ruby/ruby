# -*- racc -*-

# Copyright 2011 Sylvester Keil. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#  1. Redistributions of source code must retain the above copyright notice,
#     this list of conditions and the following disclaimer.
#
#  2. Redistributions in binary form must reproduce the above copyright notice,
#     this list of conditions and the following disclaimer in the documentation
#     and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
# EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
# INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
# OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
# EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# The views and conclusions contained in the software and documentation are
# those of the authors and should not be interpreted as representing official
# policies, either expressed or implied, of the copyright holder.

class EDTF::Parser

token T Z E X U UNKNOWN OPEN LONGYEAR UNMATCHED DOTS UA PUA

expect 0

rule

  edtf : level_0_expression
       | level_1_expression
       | level_2_expression
       ;

  # ---- Level 0 / ISO 8601 Rules ----

  # NB: level 0 intervals are covered by the level 1 interval rules
  level_0_expression : date
                     | date_time
                     ;

  date : positive_date
       | negative_date
       ;

  positive_date :
    year             { result = Date.new(val[0]).year_precision! }
    | year_month     { result = Date.new(*val.flatten).month_precision! }
    | year_month_day { result = Date.new(*val.flatten).day_precision! }
    ;

  negative_date :  '-' positive_date { result = -val[1] }


  date_time : date T time {
    result = DateTime.new(val[0].year, val[0].month, val[0].day, *val[2])
    result.skip_timezone = (val[2].length == 3)
  }

  time : base_time
       | base_time zone_offset { result = val.flatten }

  base_time : hour ':' minute ':' second { result = val.values_at(0, 2, 4) }
            | midnight

  midnight : '2' '4' ':' '0' '0' ':' '0' '0' { result = [24, 0, 0] }

  zone_offset : Z                        { result = 0 }
              | '-' zone_offset_hour     { result = -1 * val[1] }
              | '+' positive_zone_offset { result = val[1] }
              ;

  positive_zone_offset : zone_offset_hour
                       | '0' '0' ':' '0' '0' { result = 0 }
                       ;


  zone_offset_hour : d01_13 ':' minute   { result = Rational(val[0] * 60 + val[2], 1440) }
                   | '1' '4' ':' '0' '0' { result = Rational(840, 1440) }
                   | '0' '0' ':' d01_59  { result = Rational(val[3], 1440) }
                   ;

  year : digit digit digit digit {
    result = val.zip([1000,100,10,1]).reduce(0) { |s,(a,b)| s += a * b }
  }

  month : d01_12
  day : d01_31

  year_month : year '-' month { result = [val[0], val[2]] }

  # We raise an exception if there are two many days for the month, but
  # do not consider leap years, as the EDTF BNF did not either.
  # NB: an exception will be raised regardless, because the Ruby Date
  # implementation calculates leap years.
  year_month_day : year_month '-' day {
    result = val[0] << val[2]
    if result[2] > 31 || (result[2] > 30 && [2,4,6,9,11].include?(result[1])) || (result[2] > 29 && result[1] == 2)
      raise ArgumentError, "invalid date (invalid days #{result[2]} for month #{result[1]})"
    end
  }

  hour   : d00_23
  minute : d00_59
  second : d00_59

  # Completely covered by level_1_interval
  # level_0_interval : date '/' date { result = Interval.new(val[0], val[1]) }


  # ---- Level 1 Extension Rules ----

  # NB: Uncertain/approximate Dates are covered by the Level 2 rules
  level_1_expression : unspecified | level_1_interval | long_year_simple | season

  # uncertain_or_approximate_date : date UA { result = uoa(val[0], val[1]) }

  unspecified : unspecified_year
              {
                result = Date.new(val[0][0]).year_precision!
                result.unspecified.year[2,2] = val[0][1]
              }
              | unspecified_month
              | unspecified_day
              | unspecified_day_and_month
              ;

  unspecified_year :
    digit digit digit U
    {
      result = [val[0,3].zip([1000,100,10]).reduce(0) { |s,(a,b)| s += a * b }, [false,true]]
    }
    | digit digit U U
    {
      result = [val[0,2].zip([1000,100]).reduce(0) { |s,(a,b)| s += a * b }, [true, true]]
    }

  unspecified_month : year '-' U U {
    result = Date.new(val[0]).unspecified!(:month)
    result.precision = :month
  }

  unspecified_day : year_month '-' U U {
    result = Date.new(*val[0]).unspecified!(:day)
  }

  unspecified_day_and_month : year '-' U U '-' U U {
    result = Date.new(val[0]).unspecified!([:day,:month])
  }


  level_1_interval : level_1_start '/' level_1_end {
    result = Interval.new(val[0], val[2])
  }

  level_1_start : date | partial_uncertain_or_approximate | unspecified | partial_unspecified | UNKNOWN

  level_1_end : level_1_start | OPEN


  long_year_simple :
    LONGYEAR long_year
    {
      result = Date.new(val[1])
      result.precision = :year
    }
    | LONGYEAR '-' long_year
    {
      result = Date.new(-1 * val[2])
      result.precision = :year
    }
    ;

  long_year :
    positive_digit digit digit digit digit {
      result = val.zip([10000,1000,100,10,1]).reduce(0) { |s,(a,b)| s += a * b }
    }
    | long_year digit { result = 10 * val[0] + val[1] }
    ;


  season : year '-' season_number ua {
    result = Season.new(val[0], val[2])
    val[3].each { |ua| result.send(ua) }
  }

  season_number : '2' '1' { result = 21 }
                | '2' '2' { result = 22 }
                | '2' '3' { result = 23 }
                | '2' '4' { result = 24 }
                ;


  # ---- Level 2 Extension Rules ----

  # NB: Level 2 Intervals are covered by the Level 1 Interval rules.
  level_2_expression : season_qualified
                     | partial_uncertain_or_approximate
                     | partial_unspecified
                     | choice_list
                     | inclusive_list
                     | masked_precision
                     | date_and_calendar
                     | long_year_scientific
                     ;


  season_qualified : season '^' { result = val[0]; result.qualifier = val[1] }


  long_year_scientific :
    long_year_simple E integer
    {
      result = Date.new(val[0].year * 10 ** val[2]).year_precision!
    }
    | LONGYEAR int1_4 E integer
    {
      result = Date.new(val[1] * 10 ** val[3]).year_precision!
    }
    | LONGYEAR '-' int1_4 E integer
    {
      result = Date.new(-1 * val[2] * 10 ** val[4]).year_precision!
    }
    ;


  date_and_calendar : date '^' { result = val[0]; result.calendar = val[1] }


  masked_precision :
    digit digit digit X
    {
      d = val[0,3].zip([1000,100,10]).reduce(0) { |s,(a,b)| s += a * b }
      result = EDTF::Decade.new(d)
    }
    | digit digit X X
    {
      d = val[0,2].zip([1000,100]).reduce(0) { |s,(a,b)| s += a * b }
      result = EDTF::Century.new(d)
    }
    ;


  choice_list : '[' list ']'   { result = val[1].choice! }

  inclusive_list : '{' list '}' { result = val[1] }

  list : earlier                              { result = EDTF::Set.new(val[0]).earlier! }
       | earlier ',' list_elements ',' later  { result = EDTF::Set.new([val[0]] + val[2] + [val[4]]).earlier!.later! }
       | earlier ',' list_elements            { result = EDTF::Set.new([val[0]] + val[2]).earlier! }
       | earlier ',' later                    { result = EDTF::Set.new([val[0]] + [val[2]]).earlier!.later! }
       | list_elements ',' later              { result = EDTF::Set.new(val[0] + [val[2]]).later! }
       | list_elements                        { result = EDTF::Set.new(*val[0]) }
       | later                                { result = EDTF::Set.new(val[0]).later! }
       ;

  list_elements : list_element                   { result = [val[0]].flatten }
                | list_elements ',' list_element { result = val[0] + [val[2]].flatten }
                ;

  list_element : atomic
               | consecutives
               ;

  atomic : date
         | partial_uncertain_or_approximate
         | unspecified
         ;

  earlier : DOTS date { result = val[1] }

  later : year_month_day DOTS { result = Date.new(*val[0]).year_precision! }
        | year_month DOTS     { result = Date.new(*val[0]).month_precision! }
        | year DOTS           { result = Date.new(val[0]).year_precision! }
        ;

  consecutives : year_month_day DOTS year_month_day { result = (Date.new(val[0]).day_precision! .. Date.new(val[2]).day_precision!) }
               | year_month DOTS year_month         { result = (Date.new(val[0]).month_precision! .. Date.new(val[2]).month_precision!) }
               | year DOTS year                     { result = (Date.new(val[0]).year_precision! .. Date.new(val[2]).year_precision!) }
               ;

  partial_unspecified :
    unspecified_year '-' month '-' day
    {
      result = Date.new(val[0][0], val[2], val[4])
      result.unspecified.year[2,2] = val[0][1]
    }
    | unspecified_year '-' U U '-' day
    {
      result = Date.new(val[0][0], 1, val[5])
      result.unspecified.year[2,2] = val[0][1]
      result.unspecified!(:month)
    }
    | unspecified_year '-' U U '-' U U
    {
      result = Date.new(val[0][0], 1, 1)
      result.unspecified.year[2,2] = val[0][1]
      result.unspecified!([:month, :day])
    }
    | unspecified_year '-' month '-' U U
    {
      result = Date.new(val[0][0], val[2], 1)
      result.unspecified.year[2,2] = val[0][1]
      result.unspecified!(:day)
    }
    | year '-' U U '-' day
    {
      result = Date.new(val[0], 1, val[5])
      result.unspecified!(:month)
    }
    ;


  partial_uncertain_or_approximate : pua_base
    | '(' pua_base ')' UA { result = uoa(val[1], val[3]) }

  pua_base :
    pua_year             { result = val[0].year_precision! }
    | pua_year_month     { result = val[0][0].month_precision! }
    | pua_year_month_day { result = val[0].day_precision! }

  pua_year : year UA { result = uoa(Date.new(val[0]), val[1], :year) }

  pua_year_month :
    pua_year '-' month ua {
      result = [uoa(val[0].change(:month => val[2]), val[3], [:month, :year])]
    }
    | year '-' month UA {
        result = [uoa(Date.new(val[0], val[2]), val[3], [:year, :month])]
    }
    | year '-(' month ')' UA {
        result = [uoa(Date.new(val[0], val[2]), val[4], [:month]), true]
    }
    | pua_year '-(' month ')' UA {
        result = [uoa(val[0].change(:month => val[2]), val[4], [:month]), true]
    }
    ;

  pua_year_month_day :
    pua_year_month '-' day ua {
      result = uoa(val[0][0].change(:day => val[2]), val[3], val[0][1] ? [:day] : nil)
    }
    | pua_year_month '-(' day ')' UA {
        result = uoa(val[0][0].change(:day => val[2]), val[4], [:day])
    }
    | year '-(' month ')' UA day ua {
        result = uoa(uoa(Date.new(val[0], val[2], val[5]), val[4], :month), val[6], :day)
    }
    | year_month '-' day UA {
        result = uoa(Date.new(val[0][0], val[0][1], val[2]), val[3])
    }
    | year_month '-(' day ')' UA {
        result = uoa(Date.new(val[0][0], val[0][1], val[2]), val[4], [:day])
    }
    | year '-(' month '-' day ')' UA {
        result = uoa(Date.new(val[0], val[2], val[4]), val[6], [:month, :day])
    }
    | year '-(' month '-(' day ')' UA ')' UA {
        result = Date.new(val[0], val[2], val[4])
        result = uoa(result, val[6], [:day])
        result = uoa(result, val[8], [:month, :day])
    }
    | pua_year '-(' month '-' day ')' UA {
        result = val[0].change(:month => val[2], :day => val[4])
        result = uoa(result, val[6], [:month, :day])
    }
    | pua_year '-(' month '-(' day ')' UA ')' UA {
        result = val[0].change(:month => val[2], :day => val[4])
        result = uoa(result, val[6], [:day])
        result = uoa(result, val[8], [:month, :day])
    }
    # | '(' pua_year '-(' month ')' UA ')' UA '-' day ua {
    #     result = val[1].change(:month => val[3], :day => val[9])
    #     result = uoa(result, val[5], [:month])
    #     result = [uoa(result, val[7], [:year]), true]
    # }
    ;

  ua : { result = [] } | UA

  # ---- Auxiliary Rules ----

  digit : '0' { result = 0 }
        | positive_digit
        ;

  positive_digit : '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9'

  d01_12 : '0' positive_digit { result = val[1] }
         | '1' '0'            { result = 10 }
         | '1' '1'            { result = 11 }
         | '1' '2'            { result = 12 }
         ;

  d01_13 : d01_12
         | '1' '3'            { result = 13 }
         ;

  d01_23 : '0' positive_digit { result = val[1] }
         | '1' digit          { result = 10 + val[1] }
         | '2' '0'            { result = 20 }
         | '2' '1'            { result = 21 }
         | '2' '2'            { result = 22 }
         | '2' '3'            { result = 23 }
         ;

  d00_23 : '0' '0'
         | d01_23
         ;

  d01_29 : d01_23
         | '2' '4' { result = 24 }
         | '2' '5' { result = 25 }
         | '2' '6' { result = 26 }
         | '2' '7' { result = 27 }
         | '2' '8' { result = 28 }
         | '2' '9' { result = 29 }
         ;

  d01_30 : d01_29
         | '3' '0' { result = 30 }
         ;

  d01_31 : d01_30
         | '3' '1' { result = 31 }
         ;

  d01_59 : d01_29
         | '3' digit { result = 30 + val[1] }
         | '4' digit { result = 40 + val[1] }
         | '5' digit { result = 50 + val[1] }
         ;

  d00_59 : '0' '0'
         | d01_59
         ;

  int1_4 : positive_digit              { result = val[0] }
         | positive_digit digit        { result = 10 * val[0] + val[1] }
         | positive_digit digit digit
         {
           result = val.zip([100,10,1]).reduce(0) { |s,(a,b)| s += a * b }
         }
         | positive_digit digit digit digit
         {
           result = val.zip([1000,100,10,1]).reduce(0) { |s,(a,b)| s += a * b }
         }
         ;

  integer : positive_digit { result = val[0] }
          | integer digit  { result = 10 * val[0] + val[1] }
          ;



---- header
require 'strscan'

---- inner

  @defaults = {
    :level => 2,
    :debug => false
  }.freeze

  class << self; attr_reader :defaults; end

  attr_reader :options

  def initialize(options = {})
    @options = Parser.defaults.merge(options)
  end

  def debug?
    !!(options[:debug] || ENV['DEBUG'])
  end

  def parse(input)
    parse!(input)
  rescue => e
    warn e.message if debug?
    nil
  end

  def parse!(input)
    @yydebug = debug?
    @src = StringScanner.new(input)
    do_parse
  end

  def on_error(tid, value, stack)
    raise ArgumentError,
      "failed to parse date: unexpected '#{value}' at #{stack.inspect}"
  end

  def apply_uncertainty(date, uncertainty, scope = nil)
    uncertainty.each do |u|
      scope.nil? ? date.send(u) : date.send(u, scope)
    end
    date
  end

  alias uoa apply_uncertainty

  def next_token
    case
    when @src.eos?
      nil
    # when @src.scan(/\s+/)
      # ignore whitespace
    when @src.scan(/\(/)
      ['(', @src.matched]
    # when @src.scan(/\)\?~-/)
    #   [:PUA, [:uncertain!, :approximate!]]
    # when @src.scan(/\)\?-/)
    #   [:PUA, [:uncertain!]]
    # when @src.scan(/\)~-/)
    #   [:PUA, [:approximate!]]
    when @src.scan(/\)/)
      [')', @src.matched]
    when @src.scan(/\[/)
      ['[', @src.matched]
    when @src.scan(/\]/)
      [']', @src.matched]
    when @src.scan(/\{/)
      ['{', @src.matched]
    when @src.scan(/\}/)
      ['}', @src.matched]
    when @src.scan(/T/)
      [:T, @src.matched]
    when @src.scan(/Z/)
      [:Z, @src.matched]
    when @src.scan(/\?~/)
      [:UA, [:uncertain!, :approximate!]]
    when @src.scan(/\?/)
      [:UA, [:uncertain!]]
    when @src.scan(/~/)
      [:UA, [:approximate!]]
    when @src.scan(/open/i)
      [:OPEN, :open]
    when @src.scan(/unkn?own/i) # matches 'unkown' typo too
      [:UNKNOWN, :unknown]
    when @src.scan(/u/)
      [:U, @src.matched]
    when @src.scan(/x/i)
      [:X, @src.matched]
    when @src.scan(/y/)
      [:LONGYEAR, @src.matched]
    when @src.scan(/e/)
      [:E, @src.matched]
    when @src.scan(/\+/)
      ['+', @src.matched]
    when @src.scan(/-\(/)
      ['-(', @src.matched]
    when @src.scan(/-/)
      ['-', @src.matched]
    when @src.scan(/:/)
      [':', @src.matched]
    when @src.scan(/\//)
      ['/', @src.matched]
    when @src.scan(/\s*\.\.\s*/)
      [:DOTS, '..']
    when @src.scan(/\s*,\s*/)
      [',', ',']
    when @src.scan(/\^\w+/)
      ['^', @src.matched[1..-1]]
    when @src.scan(/\d/)
      [@src.matched, @src.matched.to_i]
    else @src.scan(/./)
      [:UNMATCHED, @src.rest]
    end
  end


# -*- racc -*-
