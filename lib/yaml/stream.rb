module YAML

	#
	# YAML::Stream -- for emitting many documents
	#
	class Stream

		attr_accessor :documents, :options

		def initialize( opts = {} )
			@options = opts
			@documents = []
		end
		
        def []( i )
            @documents[ i ]
        end

		def add( doc )
			@documents << doc
		end

		def edit( doc_num, doc )
			@documents[ doc_num ] = doc
		end

		def emit
            opts = @options.dup
			opts[:UseHeader] = true if @documents.length > 1
			ct = 0
            out = YAML::Syck::Emitter.new( opts )
            @documents.each { |v|
                if ct > 0
                    out << "\n--- " 
                end
                v.to_yaml( :Emitter => out )
                ct += 1
            }
            out.end_object
		end

	end

end
