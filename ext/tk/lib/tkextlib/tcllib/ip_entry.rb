#
#  tkextlib/tcllib/ip_entry.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
#   * Part of tcllib extension
#   * An IP address entry widget
#
# (The following is the original description of the library.)
#
# This package provides a widget for the entering of a IP address. 
# It guarantees a valid address at all times.

require 'tk'
require 'tkextlib/tcllib.rb'

# TkPackage.require('ipentry', '0.1')
TkPackage.require('ipentry')

module Tk
  module Tcllib
    class IP_Entry < TkEntry
      def self.package_version
        begin
          TkPackage.require('ipentry')
        rescue
          ''
        end
      end
    end
    IPEntry = IP_Entry
  end
end

class Tk::Tcllib::IP_Entry
  TkCommandNames = ['::ipentry::ipentry'.freeze].freeze
  WidgetClassName = 'IPEntry'.freeze
  WidgetClassNames[WidgetClassName] = self

  def create_self(keys)
    if keys and keys != None
      tk_call_without_enc('::ipentry::ipentry', @path, *hash_kv(keys, true))
    else
      tk_call_without_enc('::ipentry::ipentry', @path)
    end
  end
  private :create_self

  def complete?
    bool(tk_send_without_enc('complete'))
  end

  def insert(*ip)
    tk_send_without_enc('insert', array2tk_list(ip.flatten))
  end
end
