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

##
# Should we care what if somebody require this file directly?
#require 'openssl'

module OpenSSL
  module X509

    class ExtensionFactory
      def create_extension(*arg)
        if arg.size == 1 then arg = arg[0] end
        type = arg.class
        while type
          method = "create_ext_from_#{type.name.downcase}".intern
          return send(method, arg) if respond_to? method
          type = type.superclass
        end
        raise TypeError, "Don't how to create ext from #{arg.class}"
        ###send("create_ext_from_#{arg.class.name.downcase}", arg)
      end

      #
      # create_ext_from_array is built-in
      #
      def create_ext_from_string(str) # "oid = critical, value"
        unless str =~ /\s*=\s*/
          raise ArgumentError, "string in format \"oid = value\" expected"
        end
        ary = []
        ary << $`.sub(/^\s*/,"") # delete whitespaces from the beginning
        rest = $'.sub(/\s*$/,"") # delete them from the end
        if rest =~ /^critical,\s*/ # handle 'critical' option
          ary << $'
          ary << true
        else
          ary << rest
        end
        create_ext_from_array(ary)
      end
      
      #
      # Create an extention from Hash
      #   {"oid"=>sn|ln, "value"=>value, "critical"=>true|false}
      #
      def create_ext_from_hash(hash)
        unless (hash.has_key? "oid" and hash.has_key? "value")
          raise ArgumentError,
            "hash in format {\"oid\"=>..., \"value\"=>...} expected"
        end
        ary = []
        ary << hash["oid"]
        ary << hash["value"]
        ary << hash["critical"] if hash.has_key? "critical"
        create_ext_from_array(ary)
      end
    end # ExtensionFactory
    
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
    end # Extension
    
    class Attribute
      def Attribute::new(arg)
        type = arg.class
        while type
          method = "new_from_#{type.name.downcase}".intern
          return Attribute::send(method, arg) if Attribute::respond_to? method
          type = type.superclass
        end
        raise "Don't how to make new #{self} from #{arg.class}"
        ###Attribute::send("new_from_#{arg.class.name.downcase}", arg)
      end

      #
      # Attribute::new_from_array(ary) is built-in method
      #
      def Attribute::new_from_string(str) # "oid = value"
        unless str =~ /\s*=\s*/
          raise ArgumentError, "string in format \"oid = value\" expected"
        end
        ary = []
        ary << $`.sub(/^\s*/,"") # delete whitespaces from the beginning
        ary << $'.sub(/\s*$/,"") # delete them from the end
        Attribute::new_from_array(ary)
      end

      #
      # Create an attribute from Hash
      #   {"oid"=>sn|ln, "value"=>value, "critical"=>true|false}
      #
      def Attribute::new_from_hash(hash) # {"oid"=>"...", "value"=>"..."}
        unless (hash.has_key? "oid" and hash.has_key? "value")
          raise ArgumentError,
             "hash in format {\"oid\"=>..., \"value\"=>...} expected"
        end
        ary = []
        ary << hash["oid"]
        ary << hash["value"]
        Attribute::new_from_array(ary)
      end
    end # Attribute

  end # X509
end # OpenSSL
