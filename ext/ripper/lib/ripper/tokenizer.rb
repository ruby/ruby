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

    def Tokenizer.tokenize(str, filename = '-', lineno = 1)
      new(str, filename, lineno).tokenize
    end

    def initialize(src, filename = '-', lineno = 1)
      @src = src
      @__filename = filename
      @__linestart = lineno
      @__line = nil
      @__col = nil
    end

    def filename
      @__filename
    end

    def lineno
      @__line
    end

    def column
      @__col
    end

    def tokenize
      _exec_tokenizer().map {|pos, event, tok| tok }
    end

    def parse
      _exec_tokenizer().each do |pos, event, tok|
        @__line, @__col = *pos
        on__scan(event, tok)
        __send__(event, tok)
      end
    end

    private

    def _exec_tokenizer
      TokenSorter.new(@src, @__filename, @__linestart).parse
    end

  end


  class TokenSorter < ::Ripper   #:nodoc: internal use only

    def parse
      @data = []
      super
      @data.sort_by {|pos, event, tok| pos }
    end

    private

    def on__scan(event, tok)
      @data.push [[lineno(),column()], event, tok]
    end

  end

end
