# frozen_string_literal: false
=begin
= Win32 DNS and DHCP I/F

=end

module Win32
  module Resolv
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
end

begin
  require 'win32/resolv.so'
rescue LoadError
end

module Win32
#====================================================================
# Windows NT
#====================================================================
  module Resolv
    begin
      require 'win32/registry'
      module SZ
        refine Registry do
          # ad hoc workaround for broken registry
          def read_s(key)
            type, str = read(key)
            unless type == Registry::REG_SZ
              warn "Broken registry, #{name}\\#{key} was #{Registry.type2name(type)}, ignored"
              return String.new
            end
            str
          end
        end
      end
      using SZ
    rescue LoadError
      require "open3"
    end

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
        nameserver = get_dns_server_list
        slist = Registry::HKEY_LOCAL_MACHINE.open(TCPIP_NT) do |reg|
                  reg.read_s('SearchList')
                rescue Registry::Error
                  ""
                end
        search = slist.split(/,\s*/) unless slist.empty?

        if add_search = search.nil?
          search = []
          nvdom = Registry::HKEY_LOCAL_MACHINE.open(TCPIP_NT) do |reg|
                    reg.read_s('NV Domain')
                  rescue Registry::Error
                    ""
                  end

          unless nvdom.empty?
            @search = [ nvdom ]
            udmnd = Registry::HKEY_LOCAL_MACHINE.open(TCPIP_NT) do |reg|
                      reg.read_i('UseDomainNameDevolution')
                    rescue Registry::Error
                      0
                    end

            if udmnd != 0
              if /^\w+\./ =~ nvdom
                devo = $'
              end
            end
          end
        end

        ifs = Registry::HKEY_LOCAL_MACHINE.open(TCPIP_NT + '\Interfaces') do |reg|
                reg.keys
              rescue Registry::Error
                []
              end

        ifs.each do |iface|
          next unless ns = %w[NameServer DhcpNameServer].find do |key|
            ns = Registry::HKEY_LOCAL_MACHINE.open(TCPIP_NT + '\Interfaces' + "\\#{iface}" ) do |regif|
                   regif.read_s(key)
                 rescue Registry::Error
                   ""
                 end
            break ns.split(/[,\s]\s*/) unless ns.empty?
          end

          next if (nameserver & ns).empty?

          if add_search
            [ 'Domain', 'DhcpDomain' ].each do |key|
              dom = Registry::HKEY_LOCAL_MACHINE.open(TCPIP_NT + '\Interfaces' + "\\#{iface}" ) do |regif|
                      regif.read_s(key)
                    rescue Registry::Error
                      ""
                    end
              unless dom.empty?
                search.concat(dom.split(/,\s*/))
                break
              end
            end
          end
        end
        search << devo if add_search and devo
        [ search.uniq, nameserver.uniq ]
      end
    end
  end
end
