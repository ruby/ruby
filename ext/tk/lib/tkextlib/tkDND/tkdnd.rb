#
#  tkextlib/tkDND/tkdnd.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'

# call setup script for general 'tkextlib' libraries
require 'tkextlib/setup.rb'

# call setup script
require File.join(File.dirname(File.expand_path(__FILE__)), 'setup.rb')

TkPackage.require('tkdnd')

module Tk
  module TkDND
    class DND_Subst < TkUtil::CallbackSubst
      KEY_TBL = [
	[ ?a, ?l, :actions ], 
	[ ?A, ?s, :action ], 
	[ ?b, ?L, :codes ], 
	[ ?c, ?s, :code ], 
	[ ?d, ?l, :descriptions ], 
	[ ?D, ?l, :data ], 
	[ ?L, ?l, :source_types ], 
	[ ?m, ?l, :modifiers ], 
	[ ?t, ?l, :types ], 
	[ ?T, ?s, :type ], 
	[ ?W, ?w, :widget ], 
	[ ?x, ?n, :x ], 
	[ ?X, ?n, :x_root ], 
	[ ?y, ?n, :y ], 
	[ ?Y, ?n, :y_root ], 
	nil
      ]

      PROC_TBL = [
	[ ?n, TkComm.method(:num_or_str) ], 
	[ ?s, TkComm.method(:string) ], 
	[ ?l, TkComm.method(:list) ], 
	[ ?L, TkComm.method(:simplelist) ], 
	[ ?w, TkComm.method(:window) ], 
	nil
      ]

      # setup tables
      _setup_subst_table(KEY_TBL, PROC_TBL);
    end

    module DND
      def dnd_bindtarget_info(type=nil, event=nil)
	if event
	  procedure(tk_call('dnd', 'bindtarget', @path, type, event))
	elsif type
	  procedure(tk_call('dnd', 'bindtarget', @path, type))
	else
	  simplelist(tk_call('dnd', 'bindtarget', @path))
	end
      end

      def dnd_bindtarget(type, event, cmd=Proc.new, prior=50, *args)
	event = tk_event_sequence(event)
	if prior.kind_of?(Numeric)
	  tk_call('dnd', 'bindtarget', @path, type, event, 
		  install_bind_for_event_class(DND_Subst, cmd, *args), 
		  prior)
	else
	  tk_call('dnd', 'bindtarget', @path, type, event, 
		  install_bind_for_event_class(DND_Subst, cmd, prior, *args))
	end
	self
      end

      def dnd_cleartarget
	tk_call('dnd', 'cleartarget', @path)
	self
      end

      def dnd_bindsource_info(type=nil)
	if type
	  procedure(tk_call('dnd', 'bindsource', @path, type))
	else
	  simplelist(tk_call('dnd', 'bindsource', @path))
	end
      end

      def dnd_bindsource(type, cmd=Proc.new, prior=None)
	tk_call('dnd', 'bindsource', @path, type, cmd, prior)
	self
      end

      def dnd_clearsource()
	tk_call('dnd', 'clearsource', @path)
	self
      end

      def dnd_drag(keys=nil)
	tk_call('dnd', 'drag', @path, *hash_kv(keys))
	self
      end
    end
  end
end

class TkWindow
  include Tk::TkDND::DND
end
