# acl-2.0 - simple Access Control List
#
# Copyright (c) 2000,2002,2003 Masatoshi SEKI
#
# acl.rb is copyrighted free software by Masatoshi SEKI.
# You can redistribute it and/or modify it under the same terms as Ruby.

require 'ipaddr'

class ACL
  VERSION=["2.0.0"]
  class ACLEntry
    def initialize(str)
      if str == '*' or str == 'all'
	@pat = [:all]
      else
	begin
	  @pat = [:ip, IPAddr.new(str)]
	rescue ArgumentError
	  @pat = [:name, dot_pat(str)]
	end
      end
    end

    private
    def dot_pat_str(str)
      list = str.split('.').collect { |s|
	(s == '*') ? '.+' : s
      }
      list.join("\\.")
    end

    private
    def dot_pat(str)
      exp = "^" + dot_pat_str(str) + "$"
      Regexp.new(exp)
    end

    public
    def match(addr)
      case @pat[0]
      when :all
	true
      when :ip
	begin
	  ipaddr = IPAddr.new(addr[3])
	  ipaddr = ipaddr.ipv4_mapped if @pat[1].ipv6? && ipaddr.ipv4?
	rescue ArgumentError
	  return false
	end
	(@pat[1].include?(ipaddr)) ? true : false
      when :name
	(@pat[1] =~ addr[2]) ? true : false
      else
	false
      end
    end
  end

  class ACLList
    def initialize
      @list = []
    end

    public
    def match(addr)
      @list.each do |e|
	return true if e.match(addr)
      end
      false
    end

    public
    def add(str)
      @list.push(ACLEntry.new(str))
    end
  end

  DENY_ALLOW = 0
  ALLOW_DENY = 1

  def initialize(list=nil, order = DENY_ALLOW)
    @order = order
    @deny = ACLList.new
    @allow = ACLList.new
    install_list(list) if list
  end

  public
  def allow_socket?(soc)
    allow_addr?(soc.peeraddr)
  end

  public
  def allow_addr?(addr)
    case @order
    when DENY_ALLOW
      return true if @allow.match(addr)
      return false if @deny.match(addr)
      return true
    when ALLOW_DENY
      return false if @deny.match(addr)
      return true if @allow.match(addr)
      return false
    else
      false
    end
  end

  public
  def install_list(list)
    i = 0
    while i < list.size
      permission, domain = list.slice(i,2)
      case permission.downcase
      when 'allow'
	@allow.add(domain)
      when 'deny'
	@deny.add(domain)
      else
	raise "Invalid ACL entry #{list.to_s}"
      end
      i += 2
    end
  end
end

if __FILE__ == $0
  # example
  list = %w(deny all
	    allow 192.168.1.1
            allow ::ffff:192.168.1.2
            allow 192.168.1.3
            )

  addr = ["AF_INET", 10, "lc630", "192.168.1.3"]

  acl = ACL.new
  p acl.allow_addr?(addr)

  acl = ACL.new(list, ACL::DENY_ALLOW)
  p acl.allow_addr?(addr)
end

