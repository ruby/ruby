#
#  tkextlib/tcllib/cursor.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
#   * Part of tcllib extension
#   * Procedures to handle CURSOR data
#

require 'tk'
require 'tkextlib/tcllib.rb'

# TkPackage.require('cursor', '0.1')
TkPackage.require('cursor')

module Tk
  module Tcllib
    module Cursor
      def self.package_version
	begin
	  TkPackage.require('ipentry')
	rescue
	  ''
	end
      end
    end
  end

  def self.cursor_display(parent=None)
    # Pops up a dialog with a listbox containing all the cursor names. 
    # Selecting a cursor name will display it in that dialog. 
    # This is simply for viewing any available cursors on the platform .
   tk_call_without_enc('::cursor::display', parent)
  end
end

class TkWindow
  def cursor_propagate(cursor)
    # Sets the cursor for self and all its descendants to cursor. 
    tk_send_without_enc('::cursor::propagate', @path, cursor)
  end
  def cursor_restore(cursor = None)
    # Restore the original or previously set cursor for self and all its 
    # descendants. If cursor is specified, that will be used if on any 
    # widget that did not have a preset cursor (set by a previous call 
    # to TkWindow#cursor_propagate). 
    tk_send_without_enc('::cursor::restore', @path, cursor)
  end
end
