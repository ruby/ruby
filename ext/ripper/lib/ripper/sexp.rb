#
# ripper/sexp.rb
#
# Copyright (C) 2004,2005 Minero Aoki
#
# This program is free software.
# You can distribute and/or modify this program under the Ruby License.
# For details of Ruby License, see ruby/COPYING.
#

require 'ripper/core'

class Ripper

  # [EXPERIMENTAL]
  # Parses +src+ and create S-exp tree.
  # This method is for mainly developper use.
  #
  #   require 'ripper'
  #   require 'pp
  #
  #   pp Ripper.sexp("def m(a) nil end")
  #     #=> [:program,
  #          [:stmts_add,
  #           [:stmts_new],
  #           [:def,
  #            [:@ident, "m", [1, 4]],
  #            [:paren, [:params, [[:@ident, "a", [1, 6]]], nil, nil, nil]],
  #            [:bodystmt,
  #             [:stmts_add, [:stmts_new], [:var_ref, [:@kw, "nil", [1, 9]]]],
  #             nil,
  #             nil,
  #             nil]]]]
  #
  def Ripper.sexp(src, filename = '-', lineno = 1)
    SexpBuilder.new(src, filename, lineno).parse
  end

  class SexpBuilder < ::Ripper   #:nodoc:
    private

    PARSER_EVENTS.each do |event|
      module_eval(<<-End)
        def on_#{event}(*list)
          list.unshift :#{event}
          list
        end
      End
    end

    SCANNER_EVENTS.each do |event|
      module_eval(<<-End)
        def on_#{event}(tok)
          [:@#{event}, tok, [lineno(), column()]]
        end
      End
    end
  end

end
