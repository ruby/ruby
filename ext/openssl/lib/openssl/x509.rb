=begin
= $RCSfile$ -- Ruby-space definitions that completes C-space funcs for X509 and subclasses

= Info
  'OpenSSL for Ruby 2' project
  Copyright (C) 2002  Michal Rokos <m.rokos@sh.cvut.cz>
  All rights reserved.

= Licence
  This program is licenced under the same licence as Ruby.
  (See the file 'LICENCE'.)

= Version
  $Id$
=end

require "openssl"

module OpenSSL
  module X509
    class ExtensionFactory
      def create_extension(*arg)
        if arg.size > 1
          create_ext(*arg)
        else
          send("create_ext_from_"+arg[0].class.name.downcase, arg[0])
        end
      end

      def create_ext_from_array(ary)
        raise ExtensionError, "unexpected array form" if ary.size > 3 
        create_ext(ary[0], ary[1], ary[2])
      end

      def create_ext_from_string(str) # "oid = critical, value"
        oid, value = str.split(/=/, 2)
        oid.strip!
        value.strip!
        create_ext(oid, value)
      end
      
      def create_ext_from_hash(hash)
        create_ext(hash["oid"], hash["value"], hash["critical"])
      end
    end
    
    class Extension
      def to_s # "oid = critical, value"
        str = self.oid
        str << " = "
        str << "critical, " if self.critical?
        str << self.value.gsub(/\n/, ", ")
      end
        
      def to_h # {"oid"=>sn|ln, "value"=>value, "critical"=>true|false}
        {"oid"=>self.oid,"value"=>self.value,"critical"=>self.critical?}
      end

      def to_a
        [ self.oid, self.value, self.critical? ]
      end
    end

    class Name
      def self.parse(str, template=OBJECT_TYPE_TEMPLATE)
        ary = str.scan(/\s*([^\/,]+)\s*/).collect{|i| i[0].split("=", 2) }
        self.new(ary, template)
      end
    end
  end
end
