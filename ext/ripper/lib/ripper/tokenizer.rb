#
# ripper/tokenizer.rb
#
# Copyright (C) 2004 Minero Aoki
#
# This program is free software.
# You can distribute and/or modify this program under the Ruby License.
# For details of Ruby License, see ruby/COPYING.
#

class Ripper

  # Tokenizes Ruby program and returns an Array of String.
  def Ripper.tokenize(src, filename = '-', lineno = 1)
    Tokenizer.new(src, filename, lineno).tokenize
  end

  # Tokenizes Ruby program and returns an Array of Array,
  # which is formatted like [[lineno, column], type, token].
  #
  #   require 'ripper'
  #   require 'pp'
  #
  #   p Ripper.scan("def m(a) nil end")
  #     #=> [[[1,  0], :on_kw,     "def"],
  #          [[1,  3], :on_sp,     " "  ],
  #          [[1,  4], :on_ident,  "m"  ],
  #          [[1,  5], :on_lparen, "("  ],
  #          [[1,  6], :on_ident,  "a"  ],
  #          [[1,  7], :on_rparen, ")"  ],
  #          [[1,  8], :on_sp,     " "  ],
  #          [[1,  9], :on_kw,     "nil"],
  #          [[1, 12], :on_sp,     " "  ],
  #          [[1, 13], :on_kw,     "end"]]
  #
  def Ripper.scan(src, filename = '-', lineno = 1)
    Tokenizer.new(src, filename, lineno).parse
  end

  class Tokenizer < ::Ripper   #:nodoc: internal use only
    def tokenize
      parse().map {|pos, event, tok| tok }
    end

    def parse
      @buf = []
      super
      @buf.sort_by {|pos, event, tok| pos }
    end

    private

    SCANNER_EVENTS.each do |event|
      module_eval(<<-End)
        def on_#{event}(tok)
          @buf.push [[lineno(), column()], :on_#{event}, tok]
        end
      End
    end
  end

end
