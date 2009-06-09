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
        result << $1
        work.slice!(0, $&.length)
      else
        result << work.slice!(0, wrap)
      end
    end

    result << work if work.length.nonzero?
    result.join("\n").gsub(/^/, " " * indent)
  end

end

