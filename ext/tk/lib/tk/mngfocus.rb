#
#   tk/mngfocus.rb : methods for Tcl/Tk standard library 'focus.tcl'
#                           by Hidetoshi Nagai <nagai@ai.kyutech.ac.jp>
#
require 'tk'

module TkManageFocus
  extend Tk

  TkCommandNames = [
    'tk_focusFollowMouse'.freeze, 
    'tk_focusNext'.freeze, 
    'tk_focusPrev'.freeze
  ].freeze

  def TkManageFocus.followsMouse
    tk_call_without_enc('tk_focusFollowsMouse')
  end

  def TkManageFocus.next(window)
    tk_tcl2ruby(tk_call('tk_focusNext', window))
  end
  def focusNext
    TkManageFocus.next(self)
  end

  def TkManageFocus.prev(window)
    tk_tcl2ruby(tk_call('tk_focusPrev', window))
  end
  def focusPrev
    TkManageFocus.prev(self)
  end
end
