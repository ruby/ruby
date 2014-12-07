require 'rubygems'

##
# A collection of text-wrangling methods

module Gem::Text

  ##
  # Wraps +text+ to +wrap+ characters and optionally indents by +indent+
  # characters

  def format_text(text, wrap, indent=0)
    result = []
    work = text.dup

    while work.length > wrap do
      if work =~ /^(.{0,#{wrap}})[ \n]/ then
        result << $1.rstrip
        work.slice!(0, $&.length)
      else
        result << work.slice!(0, wrap)
      end
    end

    result << work if work.length.nonzero?
    result.join("\n").gsub(/^/, " " * indent)
  end

  def min3 a, b, c # :nodoc:
    if a < b && a < c then
      a
    elsif b < c then
      b
    else
      c
    end
  end

  # This code is based directly on the Text gem implementation
  # Returns a value representing the "cost" of transforming str1 into str2
  def levenshtein_distance str1, str2
    s = str1
    t = str2
    n = s.length
    m = t.length
    max = n/2

    return m if (0 == n)
    return n if (0 == m)
    return n if (n - m).abs > max

    d = (0..m).to_a
    x = nil

    str1.each_char.each_with_index do |char1,i|
      e = i+1

      str2.each_char.each_with_index do |char2,j|
        cost = (char1 == char2) ? 0 : 1
        x = min3(
             d[j+1] + 1, # insertion
             e + 1,      # deletion
             d[j] + cost # substitution
            )
        d[j] = e
        e = x
      end

      d[m] = x
    end

    return x
  end
end

