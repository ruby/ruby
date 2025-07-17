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
        get_item_property(TCPIP_NT, 'DataBasePath', expand: true)
      end

      def get_info
        search = nil
        nameserver = get_dns_server_list

        slist = get_item_property(TCPIP_NT, 'SearchList')
        search = slist.split(/,\s*/) unless slist.empty?

        if add_search = search.nil?
          search = []
          nvdom = get_item_property(TCPIP_NT, 'NV Domain')

          unless nvdom.empty?
            @search = [ nvdom ]
            udmnd = get_item_property(TCPIP_NT, 'UseDomainNameDevolution').to_i
            if udmnd != 0
              if /^\w+\./ =~ nvdom
                devo = $'
              end
            end
          end
        end

        ifs = if defined?(Win32::Registry)
                Registry::HKEY_LOCAL_MACHINE.open(TCPIP_NT + '\Interfaces') do |reg|
                  reg.keys
                rescue Registry::Error
                  []
                end
              else
                cmd = "Get-ChildItem 'HKLM:\\#{TCPIP_NT}\\Interfaces' | ForEach-Object { $_.PSChildName }"
                output, _ = Open3.capture2('powershell', '-Command', cmd)
                output.split(/\n+/)
              end

        ifs.each do |iface|
          next unless ns = %w[NameServer DhcpNameServer].find do |key|
            ns = get_item_property(TCPIP_NT + '\Interfaces' + "\\#{iface}", key)
            break ns.split(/[,\s]\s*/) unless ns.empty?
          end

          next if (nameserver & ns).empty?

          if add_search
            [ 'Domain', 'DhcpDomain' ].each do |key|
              dom = get_item_property(TCPIP_NT + '\Interfaces' + "\\#{iface}", key)
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

      def get_item_property(path, name, expand: false)
        if defined?(Win32::Registry)
          Registry::HKEY_LOCAL_MACHINE.open(path) do |reg|
            expand ? reg.read_s_expand(name) : reg.read_s(name)
          rescue Registry::Error
            ""
          end
        else
          cmd = "Get-ItemProperty -Path 'HKLM:\\#{path}' -Name '#{name}' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty '#{name}'"
          output, _ = Open3.capture2('powershell', '-Command', cmd)
          output.strip
        end
      end
    end
  end
end
