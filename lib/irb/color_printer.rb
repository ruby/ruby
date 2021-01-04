# frozen_string_literal: true
require 'pp'

module IRB
  class ColorPrinter < ::PP
    def self.pp(obj, out = $>, width = 79)
      q = ColorPrinter.new(out, width)
      q.guard_inspect_key {q.pp obj}
      q.flush
      out
    end

    def text(str, width = nil)
      unless str.is_a?(String)
        str = str.inspect
      end
      width ||= str.length

      case str
      when /\A#</, '=', '>'
        super(Color.colorize(str, [:GREEN]), width)
      else
        super(Color.colorize_code(str, ignore_error: true), width)
      end
    end
  end
end
