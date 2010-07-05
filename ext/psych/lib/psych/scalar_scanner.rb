require 'strscan'

module Psych
  ###
  # Scan scalars for built in types
  class ScalarScanner
    # Taken from http://yaml.org/type/timestamp.html
    TIME = /^\d{4}-\d{1,2}-\d{1,2}([Tt]|\s+)\d{1,2}:\d\d:\d\d(\.\d*)?(\s*Z|[-+]\d{1,2}(:\d\d)?)?/

    # Create a new scanner
    def initialize
      @string_cache = {}
    end

    # Tokenize +string+ returning the ruby object
    def tokenize string
      return nil if string.empty?
      return string if @string_cache.key?(string)

      case string
      when /^[A-Za-z~]/
        if string.length > 5
          @string_cache[string] = true
          return string
        end

        case string
        when /^[^ytonf~]/i
          @string_cache[string] = true
          string
        when '~', /^null$/i
          nil
        when /^(yes|true|on)$/i
          true
        when /^(no|false|off)$/i
          false
        else
          @string_cache[string] = true
          string
        end
      when TIME
        parse_time string
      when /^\d{4}-\d{1,2}-\d{1,2}$/
        require 'date'
        Date.strptime(string, '%Y-%m-%d')
      when /^\.inf$/i
        1 / 0.0
      when /^-\.inf$/i
        -1 / 0.0
      when /^\.nan$/i
        0.0 / 0.0
      when /^:./
        if string =~ /^:(["'])(.*)\1/
          $2.sub(/^:/, '').to_sym
        else
          string.sub(/^:/, '').to_sym
        end
      when /^[-+]?[1-9][0-9_]*(:[0-5]?[0-9])+$/
        i = 0
        string.split(':').each_with_index do |n,e|
          i += (n.to_i * 60 ** (e - 2).abs)
        end
        i
      when /^[-+]?[0-9][0-9_]*(:[0-5]?[0-9])+\.[0-9_]*$/
        i = 0
        string.split(':').each_with_index do |n,e|
          i += (n.to_f * 60 ** (e - 2).abs)
        end
        i
      else
        return Integer(string.gsub(/[,_]/, '')) rescue ArgumentError
        return Float(string.gsub(/[,_]/, '')) rescue ArgumentError
        @string_cache[string] = true
        string
      end
    end

    ###
    # Parse and return a Time from +string+
    def parse_time string
      date, time = *(string.split(/[ tT]/, 2))
      (yy, m, dd) = date.split('-').map { |x| x.to_i }
      md = time.match(/(\d+:\d+:\d+)(\.\d*)?\s*(Z|[-+]\d+(:\d\d)?)?/)

      (hh, mm, ss) = md[1].split(':').map { |x| x.to_i }
      us = (md[2] ? Rational(md[2].sub(/^\./, '0.')) : 0) * 1000000

      time = Time.utc(yy, m, dd, hh, mm, ss, us)

      return time if 'Z' == md[3]
      return Time.at(time.to_i, us) unless md[3]

      tz = md[3].split(':').map { |digit| Integer(digit.sub(/([-+])0/, '\1')) }
      offset = tz.first * 3600 + ((tz[1] || 0) * 60)
      Time.at((time - offset).to_i, us)
    end
  end
end
