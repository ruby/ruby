#
#  tkextlib/tcllib/autoscroll.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
#   * Part of tcllib extension
#   * Provides for a scrollbar to automatically mapped and unmapped as needed
#
# (The following is the original description of the library.)
#
# This package allows scrollbars to be mapped and unmapped as needed 
# depending on the size and content of the scrollbars scrolled widget. 
# The scrollbar must be managed by either pack or grid, other geometry 
# managers are not supported.
#
# When managed by pack, any geometry changes made in the scrollbars parent 
# between the time a scrollbar is unmapped, and when it is mapped will be 
# lost. It is an error to destroy any of the scrollbars siblings while the 
# scrollbar is unmapped. When managed by grid, if anything becomes gridded 
# in the same row and column the scrollbar occupied it will be replaced by 
# the scrollbar when remapped.
#
# This package may be used on any scrollbar-like widget as long as it 
# supports the set subcommand in the same style as scrollbar. If the set 
# subcommand is not used then this package will have no effect.
#

require 'tk'
require 'tk/scrollbar'

# call setup script for general 'tkextlib' libraries
require 'tkextlib/setup.rb'

# call setup script
require File.join(File.dirname(File.expand_path(__FILE__)), 'setup.rb')

# TkPackage.require('autoscroll', '1.0')
TkPackage.require('autoscroll')

module Tk
  module Scrollable
    def autoscroll(mode = nil)
      case mode
      when :x, 'x'
	if @xscrollbar
	  tk_send_without_enc('::autoscroll::autoscroll', @xscrollbar)
	end
      when :y, 'y'
	if @yscrollbar
	  tk_send_without_enc('::autoscroll::autoscroll', @yscrollbar)
	end
      when nil, :both, 'both'
	if @xscrollbar
	  tk_send_without_enc('::autoscroll::autoscroll', @xscrollbar)
	end
	if @yscrollbar
	  tk_send_without_enc('::autoscroll::autoscroll', @yscrollbar)
	end
      else
	fail ArgumentError, "'x', 'y' or 'both' (String or Symbol) is expected"
      end
      self
    end
    def unautoscroll(mode = nil)
      case mode
      when :x, 'x'
	if @xscrollbar
	  tk_send_without_enc('::autoscroll::unautoscroll', @xscrollbar)
	end
      when :y, 'y'
	if @yscrollbar
	  tk_send_without_enc('::autoscroll::unautoscroll', @yscrollbar)
	end
      when nil, :both, 'both'
	if @xscrollbar
	  tk_send_without_enc('::autoscroll::unautoscroll', @xscrollbar)
	end
	if @yscrollbar
	  tk_send_without_enc('::autoscroll::unautoscroll', @yscrollbar)
	end
      else
	fail ArgumentError, "'x', 'y' or 'both' (String or Symbol) is expected"
      end
      self
    end
  end
end

class TkScrollbar
  def autoscroll
    # Arranges for the already existing scrollbar to be mapped 
    # and unmapped as needed.
    tk_send_without_enc('::autoscroll::autoscroll', @path)
    self
  end
  def unautoscroll
    #     Returns the scrollbar to its original static state. 
    tk_send_without_enc('::autoscroll::unautoscroll', @path)
    self
  end
end
