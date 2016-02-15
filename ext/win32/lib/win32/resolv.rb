# frozen_string_literal: false
=begin
= Win32 DNS and DHCP I/F

=end

require 'win32/registry'

module Win32
  module Resolv
    API = Registry::API

    def self.get_hosts_path
      path = get_hosts_dir
      path = File.expand_path('hosts', path)
      File.exist?(path) ? path : nil
    end

    def self.get_resolv_info
      search, nameserver = get_info
      if search.empty?
        search = nil
      else
        search.delete("")
        search.uniq!
      end
      if nameserver.empty?
        nameserver = nil
      else
        nameserver.delete("")
        nameserver.delete("0.0.0.0")
        nameserver.uniq!
      end
      [ search, nameserver ]
    end
  end

kernel32 = Module.new do
  extend Importer
  dlload "kernel32"
end
getv = kernel32.extern "int GetVersionExA(void *)", :stdcall
info = [ 148, 0, 0, 0, 0 ].pack('V5') + "\0" * 128
getv.call(info)
if info.unpack('V5')[4] == 2  # VER_PLATFORM_WIN32_NT
#====================================================================
# Windows NT
#====================================================================
  module Resolv
    TCPIP_NT = 'SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'

    class << self
      private
      def get_hosts_dir
        Registry::HKEY_LOCAL_MACHINE.open(TCPIP_NT) do |reg|
          reg.read_s_expand('DataBasePath')
        end
      end

      def get_info
        search = nil
        nameserver = []
        Registry::HKEY_LOCAL_MACHINE.open(TCPIP_NT) do |reg|
          begin
            slist = reg.read_s('SearchList')
            search = slist.split(/,\s*/) unless slist.empty?
          rescue Registry::Error
          end

          if add_search = search.nil?
            search = []
            begin
              nvdom = reg.read_s('NV Domain')
              unless nvdom.empty?
                @search = [ nvdom ]
                if reg.read_i('UseDomainNameDevolution') != 0
                  if /^\w+\./ =~ nvdom
                    devo = $'
                  end
                end
              end
            rescue Registry::Error
            end
          end

          reg.open('Interfaces') do |h|
            h.each_key do |iface, |
              h.open(iface) do |regif|
                begin
                  [ 'NameServer', 'DhcpNameServer' ].each do |key|
                    begin
                      ns = regif.read_s(key)
                    rescue
                    else
                      unless ns.empty?
                        nameserver.concat(ns.split(/[,\s]\s*/))
                        break
                      end
                    end
                  end
                rescue Registry::Error
                end

                if add_search
                  begin
                    [ 'Domain', 'DhcpDomain' ].each do |key|
                      dom = regif.read_s(key)
                      unless dom.empty?
                        search.concat(dom.split(/,\s*/))
                        break
                      end
                    end
                  rescue Registry::Error
                  end
                end
              end
            end
          end
          search << devo if add_search and devo
        end
        [ search.uniq, nameserver.uniq ]
      end
    end
  end
else
  require_relative 'resolv9x'
end
end
