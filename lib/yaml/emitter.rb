#
# Output classes and methods
#

require 'yaml/baseemitter'
require 'yaml/encoding'

module YAML

	#
	# Emit a set of values
	#
    
	class Emitter

        include BaseEmitter

		attr_accessor :options

		def initialize( opts )
			opts = {} if opts.class != Hash
			@options = YAML::DEFAULTS.dup.update( opts )
            @headless = 0
            @seq_map = false
            @anchors = {}
            @anchor_extras = {}
            @active_anchors = []
            @level = -1
            self.clear
		end

		def clear
			@buffer = []
		end

        def level
            @level
        end

		#
		# Version string
		#
		def version_s
			" %YAML:#{@options[:Version]}" if @options[:UseVersion]
		end

		#
		# Header
		#
		def header
            if @headless.nonzero?
                ""
            else
                "---#{version_s} "
            end
		end

		#
		# Concatenate to the buffer
		#
		def <<( str )
            #p [ self.id, @level, str ]
			@buffer.last << str
		end

        #
        # Monitor objects and allow references
        #
        def start_object( oid )
		    @level += 1
            @buffer.push( "" )
            #p [ self.id, @level, :OPEN ]
            idx = nil
            if oid
                if @anchors.has_key?( oid )
                    idx = @active_anchors.index( oid )
                    unless idx
                        idx = @active_anchors.length
                        af_str = "&#{@options[:AnchorFormat]} " % [ idx + 1 ]
                        af_str += @anchor_extras[ @anchors[ oid ] ].to_s
                        @buffer[ @anchors[ oid ] ][0,0] = af_str
					    @headless = 0 if @anchors[ oid ].zero?
                    end
                    idx += 1
                    @active_anchors.push( oid )
                else
                    @anchors[ oid ] = @buffer.length - 1
                end
            end
            return idx
        end

		#
		# Output method
		#
		def end_object
		    @level -= 1
            @buffer.push( "" )
            #p [ self.id, @level, :END ]
			if @level < 0
				header + @buffer.to_s[@headless..-1].to_s
			end
		end
	end

end

