#												vim:sw=4:ts=4
# $Id$
#
#   YAML.rb
#
#   Loads the parser/loader and emitter/writer.
#

module YAML

    begin
        require 'yaml/syck'
        @@parser = YAML::Syck::Parser
        @@loader = YAML::Syck::DefaultLoader
    rescue LoadError
        require 'yaml/parser'
        @@parser = YAML::Parser
        @@loader = YAML::DefaultLoader
    end
    require 'yaml/emitter'
    require 'yaml/loader'
    require 'yaml/stream'

	#
	# Load a single document from the current stream
	#
	def YAML.load( io )
		yp = @@parser.new.load( io )
	end

	#
	# Parse a single document from the current stream
	#
	def YAML.parse( io )
		yp = @@parser.new( :Model => :Generic ).load( io )
	end

	#
	# Load all documents from the current stream
	#
	def YAML.each_document( io, &doc_proc )
		yp = @@parser.new.load_documents( io, &doc_proc )
    end

	#
	# Identical to each_document
	#
	def YAML.load_documents( io, &doc_proc )
		YAML.each_document( io, &doc_proc )
    end

	#
	# Parse all documents from the current stream
	#
	def YAML.each_node( io, &doc_proc )
		yp = @@parser.new( :Model => :Generic ).load_documents( io, &doc_proc )
    end

	#
	# Parse all documents from the current stream
	#
	def YAML.parse_documents( io, &doc_proc )
		YAML.each_node( io, &doc_proc )
    end

	#
	# Load all documents from the current stream
	#
	def YAML.load_stream( io )
		yp = @@parser.new
		d = nil
		yp.load_documents( io ) { |doc|
			d = YAML::Stream.new( yp.options ) if not d
			d.add( doc ) 
		}
		return d
	end

	#
	# Add a transfer method to a domain
	#
	def YAML.add_domain_type( domain, type_re, &transfer_proc )
        @@loader.add_domain_type( domain, type_re, &transfer_proc )
	end

	#
	# Add a transfer method for a builtin type
	#
	def YAML.add_builtin_type( type_re, &transfer_proc )
	    @@loader.add_builtin_type( type_re, &transfer_proc )
	end

	#
	# Add a transfer method for a builtin type
	#
	def YAML.add_ruby_type( type, &transfer_proc )
        @@loader.add_ruby_type( type, &transfer_proc )
	end

	#
	# Add a private document type
	#
	def YAML.add_private_type( type_re, &transfer_proc )
	    @@loader.add_private_type( type_re, &transfer_proc )
	end

    #
    # Detect typing of a string
    #
    def YAML.detect_implicit( val )
        @@loader.detect_implicit( val )
    end

    #
    # Apply a transfer method to a Ruby object
    #
    def YAML.transfer( type_id, obj )
        @@loader.transfer( type_id, obj )
    end

    #
    # Method to extract colon-seperated type and class, returning
    # the type and the constant of the class
    #
    def YAML.read_type_class( type, obj_class )
        scheme, domain, type, tclass = type.split( ':', 4 )
        tclass.split( "::" ).each { |c| obj_class = obj_class.const_get( c ) } if tclass
        return [ type, obj_class ]
    end

    #
    # Allocate blank object
    #
    def YAML.object_maker( obj_class, val, is_attr = false )
        if Hash === val
            name = obj_class.name
            ostr = sprintf( "\004\006o:%c%s\000", name.length + 5, name )
            if is_attr
                ostr[ -1, 1 ] = Marshal.dump( val ).sub( /^[^{]+\{/, '' )
				p ostr
            end
            o = ::Marshal.load( ostr )
            unless is_attr
                val.each_pair { |k,v|
                    o.instance_eval "@#{k} = v"
                }
            end
            o
        else
            raise YAML::Error, "Invalid object explicitly tagged !ruby/Object: " + val.inspect
        end
    end

end

require 'yaml/rubytypes'
require 'yaml/types'

#
# ryan: You know how Kernel.p is a really convenient way to dump ruby
#       structures?  The only downside is that it's not as legible as
#       YAML.
#
# _why: (listening)
#
# ryan: I know you don't want to urinate all over your users' namespaces.
#       But, on the other hand, convenience of dumping for debugging is,
#       IMO, a big YAML use case.
#
# _why: Go nuts!  Have a pony parade!
#
# ryan: Either way, I certainly will have a pony parade.
#
module Kernel
    def y( x )
        puts x.to_yaml
    end
end


