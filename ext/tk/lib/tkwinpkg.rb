#
#   tkwinpkg.rb : methods for Tcl/Tk packages for Microsoft Windows
#                     2000/11/22 by Hidetoshi Nagai <nagai@ai.kyutech.ac.jp>
#
#     ATTENTION !!
#         This is NOT TESTED. Because I have no test-environment.
#
#
require 'tk'

module TkWinDDE
  extend Tk
  extend TkWinDDE

  TkCommandNames = ['dde'.freeze].freeze

  tk_call('package', 'require', 'dde')

  def servername(topic=nil)
    tk_call('dde', 'servername', topic)
  end

  def execute(service, topic, data)
    tk_call('dde', 'execute', service, topic, data)
  end

  def async_execute(service, topic, data)
    tk_call('dde', '-async', 'execute', service, topic, data)
  end

  def poke(service, topic, item, data)
    tk_call('dde', 'poke', service, topic, item, data)
  end

  def request(service, topic, item)
    tk_call('dde', 'request', service, topic, item)
  end

  def services(service, topic)
    tk_call('dde', 'services', service, topic)
  end

  def eval(topic, cmd, *args)
    tk_call('dde', 'eval', topic, cmd, *args)
  end

  module_function :servername, :execute, :async_execute, 
                  :poke, :request, :services, :eval
end

module TkWinRegistry
  extend Tk
  extend TkWinRegistry

  TkCommandNames = ['registry'.freeze].freeze

  tk_call('package', 'require', 'registry')

  def delete(keynam, valnam=nil)
    tk_call('registry', 'delete', keynam, valnam)
  end

  def get(keynam, valnam)
    tk_call('registry', 'get', keynam, valnam)
  end

  def keys(keynam)
    tk_split_simplelist(tk_call('registry', 'keys', keynam))
  end

  def set(keynam, valnam=nil, data=nil, dattype=nil)
    tk_call('registry', 'set', keynam, valnam, data, dattype)
  end

  def type(keynam, valnam)
    tk_call('registry', 'type', keynam, valnam)
  end

  def values(keynam)
    tk_split_simplelist(tk_call('registry', 'values', keynam))
  end

  module_function :delete, :get, :keys, :set, :type, :values
end
