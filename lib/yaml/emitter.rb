#
# Output classes and methods
#

require 'yaml/constants'
require 'yaml/encoding'
require 'yaml/error'

module YAML

	#
	# Emit a set of values
	#
    
	class Emitter
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
        # Emit binary data
        #
        def binary_base64( value )
            self << "!binary "
            self.node_text( [value].pack("m"), '|' )
        end

		#
		# Emit plain, normal flowing text
		#
		def node_text( value, block = '>' )
            @seq_map = false
			valx = value.dup
			if @options[:UseBlock]
				block = '|'
			elsif not @options[:UseFold] and valx =~ /\n[ \t]/ and not valx =~ /#{YAML::ESCAPE_CHAR}/
				block = '|'
			end 
			str = block.dup
			if valx =~ /\n\Z\n/
				str << "+"
			elsif valx =~ /\Z\n/
			else
				str << "-"
			end
			if valx =~ /#{YAML::ESCAPE_CHAR}/
				valx = YAML::escape( valx )
			end
			if valx =~ /\A[ \t#]/
				str << @options[:Indent].to_s
			end
			if block == '>'
				valx = fold( valx ) 
			end
			self << str + indent_text( valx ) + "\n"
		end

		#
		# Emit a simple, unqouted string
		#
		def simple( value )
            @seq_map = false
            self << value.to_s
		end

		#
		# Emit double-quoted string
		#
		def double( value )
			"\"#{YAML.escape( value )}\"" 
		end

		#
		# Emit single-quoted string
		#
		def single( value )
			"'#{value}'"
		end

		#
		# Write a text block with the current indent
		#
		def indent_text( text )
			return "" if text.to_s.empty?
            spacing = " " * ( @level * @options[:Indent] )
			return "\n" + text.gsub( /^([^\n])/, "#{spacing}\\1" )
		end

		#
		# Write a current indent
		#
		def indent
            #p [ self.id, @level, :INDENT ]
			return " " * ( @level * @options[:Indent] )
		end

		#
		# Add indent to the buffer
		#
		def indent!
			self << indent
		end

		#
		# Folding paragraphs within a column
		#
		def fold( value )
			value.gsub!( /\A\n+/, '' )
			folded = $&.to_s
			width = (0..@options[:BestWidth])
			while not value.empty?
				last = value.index( /(\n+)/ )
				chop_s = false
				if width.include?( last )
					last += $1.length - 1
				elsif width.include?( value.length )
					last = value.length
				else
					last = value.rindex( /[ \t]/, @options[:BestWidth] )
					chop_s = true
				end
				folded += value.slice!( 0, width.include?( last ) ? last + 1 : @options[:BestWidth] )
				folded.chop! if chop_s
				folded += "\n" unless value.empty?
			end
			folded
		end

        #
        # Quick mapping
        #
        def map( type, &e )
            val = Mapping.new
            e.call( val )
			self << "#{type} " if type.length.nonzero?

			#
			# Empty hashes
			#
			if val.length.zero?
				self << "{}"
                @seq_map = false
			else
                if @buffer.length == 1 and @options[:UseHeader] == false and type.length.zero? 
			        @headless = 1 
                end

                defkey = @options.delete( :DefaultKey )
                if defkey
                    seq_map_shortcut
                    self << "= : "
                    defkey.to_yaml( :Emitter => self )
                end

				#
				# Emit the key and value
				#
                val.each { |v|
                    seq_map_shortcut
                    if v[0].is_complex_yaml?
                        self << "? "
                    end
                    v[0].to_yaml( :Emitter => self )
                    if v[0].is_complex_yaml?
                        self << "\n"
                        indent!
                    end
                    self << ": " 
                    v[1].to_yaml( :Emitter => self )
                }
			end
        end

        def seq_map_shortcut
            if @seq_map
                @anchor_extras[@buffer.length - 1] = "\n" + indent
                @seq_map = false
            else
                self << "\n"
                indent! 
            end
        end

        #
        # Quick sequence
        #
        def seq( type, &e )
            @seq_map = false
            val = Sequence.new
            e.call( val )
			self << "#{type} " if type.length.nonzero?

			#
			# Empty arrays
			#
			if val.length.zero?
				self << "[]"
			else
                if @buffer.length == 1 and @options[:UseHeader] == false and type.length.zero? 
			        @headless = 1 
                end
				#
				# Emit the key and value
				#
                val.each { |v|
                    self << "\n"
                    indent!
                    self << "- "
                    @seq_map = true if v.class == Hash
                    v.to_yaml( :Emitter => self )
                }
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
				header + @buffer.to_s[@headless..-1]
			end
		end
	end

    #
    # Emitter helper classes
    #
    class Mapping < Array
        def add( k, v )
            push [k, v]
        end
    end

    class Sequence < Array
        def add( v )
            push v
        end
    end

	#
	# Allocate an Emitter if needed
	#
	def YAML.quick_emit( oid, opts = {}, &e )
		old_opt = nil
		if opts[:Emitter].is_a? YAML::Emitter
			out = opts.delete( :Emitter )
			old_opt = out.options.dup
			out.options.update( opts )
		else
			out = YAML::Emitter.new( opts )
		end
        aidx = out.start_object( oid )
        if aidx
            out.simple( "*#{out.options[:AnchorFormat]} " % [ aidx ] )
        else
            e.call( out )
        end
		if old_opt.is_a? Hash
			out.options = old_opt
		end 
		out.end_object
	end
	
end

