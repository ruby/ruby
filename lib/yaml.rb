#												vim:sw=4:ts=4
# $Id$
#
#   YAML.rb
#
#   Loads the parser/loader and emitter/writer.
#

module YAML

    begin
        require 'syck'
        Parser = YAML::Syck::Parser
    rescue LoadError
        require 'yaml/parser'
        Parser = YAML::Parser
    end
    require 'yaml/emitter'
    require 'yaml/rubytypes'

    #
    # Allocate blank object
    #
    def YAML.object_maker( obj_class, val )
        if Hash === val
            name = obj_class.name
            o = ::Marshal.load( sprintf( "\004\006o:%c%s\000", name.length + 5, name ))
            val.each_pair { |k,v|
                o.instance_eval "@#{k} = v"
            }
            o
        else
            raise YAML::Error, "Invalid object explicitly tagged !ruby/Object: " + val.inspect
        end
    end

	#
	# Input methods
	#

	#
	# Load a single document from the current stream
	#
	def YAML.load( io )
		yp = YAML::Parser.new.parse( io )
	end

	#
	# Parse a single document from the current stream
	#
	def YAML.parse( io )
		yp = YAML::Parser.new( :Model => :Generic ).parse( io )
	end

	#
	# Load all documents from the current stream
	#
	def YAML.each_document( io, &doc_proc )
		yp = YAML::Parser.new.parse_documents( io, &doc_proc )
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
		yp = YAML::Parser.new( :Model => :Generic ).parse_documents( io, &doc_proc )
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
		yp = YAML::Parser.new
		d = nil
		yp.parse_documents( io ) { |doc|
			d = YAML::Stream.new( yp.options ) if not d
			d.add( doc ) 
		}
		return d
	end

end

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


