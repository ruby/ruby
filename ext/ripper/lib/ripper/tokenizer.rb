#
# ripper/tokenizer.rb
#
# Copyright (C) 2004 Minero Aoki
#
# This program is free software.
# You can distribute and/or modify this program under the Ruby License.
# For details of Ruby License, see ruby/COPYING.
#

require 'ripper'

class Ripper

  def Ripper.tokenize(str)
    Tokenizer.tokenize(str)
  end

  class Tokenizer < ::Ripper
    def Tokenizer.tokenize(str)
      new(str).tokenize
    end

    def tokenize
      @tokens = []
      parse
      @tokens.sort_by {|tok, pos| pos }.map {|tok,| tok }
    end

    private

    def on__scan(type, tok)
      @tokens.push [tok, [lineno(),column()]]
    end
  end

end
