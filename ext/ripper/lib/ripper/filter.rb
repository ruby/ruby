#
# ripper/filter.rb
#
# Copyright (C) 2004 Minero Aoki
#
# This program is free software.
# You can distribute and/or modify this program under the Ruby License.
# For details of Ruby License, see ruby/COPYING.
#

require 'ripper'

class Ripper

  class Filter

    def initialize(src, filename = '-', lineno = 1)
      @__parser = Tokenizer.new(src, filename, lineno)
      @__line = nil
      @__col = nil
    end

    def filename
      @__parser.filename
    end

    def lineno
      @__line
    end

    def column
      @__col
    end

    def parse(init)
      data = init
      @__parser.parse.each do |pos, event, tok|
        @__line, @__col = *pos
        data = if respond_to?(event, true)
               then __send__(event, tok, data)
               else on_default(event, tok, data)
               end
      end
      data
    end

    private

    def on_default(event, tok, data)
      data
    end

  end

end
