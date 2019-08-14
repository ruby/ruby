require 'drb/acl'

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
