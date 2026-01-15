# frozen_string_literal: false
=begin
= Win32 DNS and DHCP I/F

=end

require 'win32/resolv.so'

module Win32
  module Resolv
    # Error at Win32 API
    class Error < StandardError
      # +code+ Win32 Error code
      # +message+ Formatted message for +code+
      def initialize(code, message)
        super(message)
        @code = code
      end

      # Win32 error code
      attr_reader :code
    end

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

    class << self
      private
      def get_hosts_dir
        tcpip_params do |params|
          params.value('DataBasePath')
        end
      end

      def get_info
        search = nil
        nameserver = get_dns_server_list

        tcpip_params do |params|
          slist = params.value('SearchList')
          search = slist.split(/,\s*/) if slist and !slist.empty?

          if add_search = search.nil?
            search = []
            domain = params.value('Domain')

            if domain and !domain.empty?
              search = [ domain ]
              udmnd = params.value('UseDomainNameDevolution')
              if udmnd&.nonzero?
                if /^\w+\./ =~ domain
                  devo = $'
                end
              end
            end
          end

          params.open('Interfaces') do |reg|
            reg.each_key do |iface|
              next unless ns = %w[NameServer DhcpNameServer].find do |key|
                ns = iface.value(key)
                break ns.split(/[,\s]\s*/) if ns and !ns.empty?
              end

              next if (nameserver & ns).empty?

              if add_search
                [ 'Domain', 'DhcpDomain' ].each do |key|
                  dom = iface.value(key)
                  if dom and !dom.empty?
                    search.concat(dom.split(/,\s*/))
                    break
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
end
