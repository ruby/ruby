#
# BaseEmitter
#

require 'yaml/constants'
require 'yaml/encoding'
require 'yaml/error'

module YAML

    module BaseEmitter

        def options( opt = nil )
            if opt
                @options[opt] || YAML::DEFAULTS[opt]
            else
                @options
            end
        end

        def options=( opt )
            @options = opt
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
            unless block
                block =
                    if options(:UseBlock)
                        '|'
                    elsif not options(:UseFold) and valx =~ /\n[ \t]/ and not valx =~ /#{YAML::ESCAPE_CHAR}/
                        '|'
                    else
                        '>'
                    end 
                if valx =~ /\A[ \t#]/
                    block += options(:Indent).to_s
                end
                block +=
                    if valx =~ /\n\Z\n/
                        "+"
                    elsif valx =~ /\Z\n/
                        ""
                    else
                        "-"
                    end
            end
            if valx =~ /#{YAML::ESCAPE_CHAR}/
                valx = YAML::escape( valx )
            end
            if block[0] == ?> 
                valx = fold( valx ) 
            end
            indt = nil
            indt = $&.to_i if block =~ /\d+/
            self << block + indent_text( valx, indt ) + "\n"
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
        def indent_text( text, indt = nil )
            return "" if text.to_s.empty?
            indt ||= 0
            spacing = indent( indt )
            return "\n" + text.gsub( /^([^\n])/, "#{spacing}\\1" )
        end

        #
        # Write a current indent
        #
        def indent( mod = nil )
            #p [ self.id, @level, :INDENT ]
            if level.zero?
                mod ||= 0
            else
                mod ||= options(:Indent)
                mod += ( level - 1 ) * options(:Indent)
            end
            return " " * mod
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
            width = (0..options(:BestWidth))
            while not value.empty?
                last = value.index( /(\n+)/ )
                chop_s = false
                if width.include?( last )
                    last += $1.length - 1
                elsif width.include?( value.length )
                    last = value.length
                else
                    last = value.rindex( /[ \t]/, options(:BestWidth) )
                    chop_s = true
                end
                folded += value.slice!( 0, width.include?( last ) ? last + 1 : options(:BestWidth) )
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
                # FIXME
                # if @buffer.length == 1 and options(:UseHeader) == false and type.length.zero? 
                #     @headless = 1 
                # end

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
            # FIXME: seq_map needs to work with the new anchoring system
            # if @seq_map
            #     @anchor_extras[@buffer.length - 1] = "\n" + indent
            #     @seq_map = false
            # else
                self << "\n"
                indent! 
            # end
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
                # FIXME
                # if @buffer.length == 1 and options(:UseHeader) == false and type.length.zero? 
                #     @headless = 1 
                # end

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

end
