#
#  tkbgerror -- bgerror ( tkerror ) module
#                     1998/07/16 by Hidetoshi Nagai <nagai@ai.kyutech.ac.jp>
#
require 'tk'

module TkBgError
  extend Tk

  def bgerror(message)
    tk_call 'bgerror', message
  end
  alias tkerror bgerror
  alias show bgerror

  module_function :bgerror, :tkerror, :show
end
