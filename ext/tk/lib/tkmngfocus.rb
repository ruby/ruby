#
#   tkmngfocus.rb : methods for Tcl/Tk standard library 'focus.tcl'
#                     1998/07/16 by Hidetoshi Nagai <nagai@ai.kyutech.ac.jp>
#
require 'tk'

module TkManageFocus
  extend Tk

  def TkManageFocus.followsMouse
    tk_call 'tk_focusFollowsMouse'
  end

  def TkManageFocus.next(window)
    tk_call 'tk_focusNext', window
  end
  def focusNext
    TkManageFocus.next(self)
  end

  def TkManageFocus.prev(window)
    tk_call 'tk_focusPrev', window
  end
  def focusPrev
    TkManageFocus.prev(self)
  end
end
