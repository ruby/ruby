# frozen_string_literal: false
require 'strscan'

module Psych
  ###
  # Scan scalars for built in types
  class ScalarScanner
    # Taken from http://yaml.org/type/timestamp.html
    TIME = /^-?\d{4}-\d{1,2}-\d{1,2}(?:[Tt]|\s+)\d{1,2}:\d\d:\d\d(?:\.\d*)?(?:\s*(?:Z|[-+]\d{1,2}:?(?:\d\d)?))?$/

    # Taken from http://yaml.org/type/float.html
    FLOAT = /^(?:[-+]?([0-9][0-9_,]*)?\.[0-9]*([eE][-+][0-9]+)?(?# base 10)
              |[-+]?[0-9][0-9_,]*(:[0-5]?[0-9])+\.[0-9_]*(?# base 60)
              |[-+]?\.(inf|Inf|INF)(?# infinity)
              |\.(nan|NaN|NAN)(?# not a number))$/x

    # Taken from http://yaml.org/type/int.html
    INTEGER = /^(?:[-+]?0b[0-1_]+          (?# base 2)
                  |[-+]?0[0-7_]+           (?# base 8)
                  |[-+]?(?:0|[1-9][0-9_]*) (?# base 10)
                  |[-+]?0x[0-9a-fA-F_]+    (?# base 16))$/x

    attr_reader :class_loader

    # Create a new scanner
    def initialize class_loader
      @string_cache = {}
      @symbol_cache = {}
      @class_loader = class_loader
    end

    # Tokenize +string+ returning the Ruby object
    def tokenize string
      return nil if string.empty?
      return string if @string_cache.key?(string)
      return @symbol_cache[string] if @symbol_cache.key?(string)

      case string
      # Check for a String type, being careful not to get caught by hash keys, hex values, and
      # special floats (e.g., -.inf).
      when /^[^\d\.:-]?[A-Za-z_\s!@#\$%\^&\*\(\)\{\}\<\>\|\/\\~;=]+/, /\n/
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
        begin
          parse_time string
        rescue ArgumentError
          string
        end
      when /^\d{4}-(?:1[012]|0\d|\d)-(?:[12]\d|3[01]|0\d|\d)$/
        require 'date'
        begin
          class_loader.date.strptime(string, '%Y-%m-%d')
        rescue ArgumentError
          string
        end
      when /^\.inf$/i
        Float::INFINITY
      when /^-\.inf$/i
        -Float::INFINITY
      when /^\.nan$/i
        Float::NAN
      when /^:./
        if string =~ /^:(["'])(.*)\1/
          @symbol_cache[string] = class_loader.symbolize($2.sub(/^:/, ''))
        else
          @symbol_cache[string] = class_loader.symbolize(string.sub(/^:/, ''))
        end
      when /^[-+]?[0-9][0-9_]*(:[0-5]?[0-9])+$/
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
      when FLOAT
        if string =~ /\A[-+]?\.\Z/
          @string_cache[string] = true
          string
        else
          Float(string.gsub(/[,_]|\.([Ee]|$)/, '\1'))
        end
      else
        int = parse_int string.gsub(/[,_]/, '')
        return int if int

        @string_cache[string] = true
        string
      end
    end

    ###
    # Parse and return an int from +string+
    def parse_int string
      return unless INTEGER === string
      Integer(string)
    end

    ###
    # Parse and return a Time from +string+
    def parse_time string
      klass = class_loader.load 'Time'

      date, time = *(string.split(/[ tT]/, 2))
      (yy, m, dd) = date.match(/^(-?\d{4})-(\d{1,2})-(\d{1,2})/).captures.map { |x| x.to_i }
      md = time.match(/(\d+:\d+:\d+)(?:\.(\d*))?\s*(Z|[-+]\d+(:\d\d)?)?/)

      (hh, mm, ss) = md[1].split(':').map { |x| x.to_i }
      us = (md[2] ? Rational("0.#{md[2]}") : 0) * 1000000

      time = klass.utc(yy, m, dd, hh, mm, ss, us)

      return time if 'Z' == md[3]
      return klass.at(time.to_i, us) unless md[3]

      tz = md[3].match(/^([+\-]?\d{1,2})\:?(\d{1,2})?$/)[1..-1].compact.map { |digit| Integer(digit, 10) }
      offset = tz.first * 3600

      if offset < 0
        offset -= ((tz[1] || 0) * 60)
      else
        offset += ((tz[1] || 0) * 60)
      end

      klass.at((time - offset).to_i, us)
    end
  end
end
