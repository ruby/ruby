require 'date'
#
# Type conversions
#

class Class
	def to_yaml( opts = {} )
		raise ArgumentError, "can't dump anonymous class %s" % self.class
	end
end

class Object
    def is_complex_yaml?
        true
    end
    def to_yaml_type
        "!ruby/object:#{self.class}"
    end
    def to_yaml_properties
        instance_variables.sort
    end
	def to_yaml( opts = {} )
		YAML::quick_emit( self.object_id, opts ) { |out|
            out.map( self.to_yaml_type ) { |map|
				to_yaml_properties.each { |m|
                    map.add( m[1..-1], instance_eval( m ) )
                }
            }
		}
	end
end

YAML.add_ruby_type( 'object' ) { |type, val|
    type, obj_class = YAML.read_type_class( type, Object )
    YAML.object_maker( obj_class, val )
}

#
# Maps: Hash#to_yaml
#
class Hash
    def is_complex_yaml?
        true
    end
    def to_yaml_type
        if self.class == Hash or self.class == YAML::SpecialHash
            "!map"
        else
            "!ruby/hash:#{self.class}"
        end
    end
	def to_yaml( opts = {} )
		opts[:DocType] = self.class if Hash === opts
		YAML::quick_emit( self.object_id, opts ) { |out|
            hash_type = to_yaml_type
            if not out.options[:ExplicitTypes] and hash_type == "!map"
                hash_type = ""
            end
            out.map( hash_type ) { |map|
				#
				# Sort the hash
				#
                if out.options[:SortKeys]
				    map.concat( self.sort )
                else
                    map.concat( self.to_a )
                end
            }
		}
	end
end

hash_proc = Proc.new { |type, val|
	if Array === val
 		val = Hash.[]( *val )		# Convert the map to a sequence
	elsif Hash === val
	    type, obj_class = YAML.read_type_class( type, Hash )
        if obj_class != Hash
            o = obj_class.new
            o.update( val )
            val = o
        end
    else
 		raise YAML::Error, "Invalid map explicitly tagged !map: " + val.inspect
	end
	val
}
YAML.add_builtin_type( 'map', &hash_proc )
YAML.add_ruby_type( 'hash', &hash_proc ) 

module YAML

    #
    # Ruby-specific collection: !ruby/flexhash
    #
    class FlexHash < Array
        def []( k )
            self.assoc( k ).to_a[1]
        end
        def []=( k, *rest )
            val, set = rest.reverse
            if ( tmp = self.assoc( k ) ) and not set
                tmp[1] = val
            else
                self << [ k, val ] 
            end
            val
        end
        def has_key?( k )
            self.assoc( k ) ? true : false
        end
        def is_complex_yaml?
            true
        end
        def to_yaml( opts = {} )
            YAML::quick_emit( self.object_id, opts ) { |out|
                out.seq( "!ruby/flexhash" ) { |seq|
                    self.each { |v|
                        if v[1]
                            seq.add( Hash.[]( *v ) )
                        else
                            seq.add( v[0] )
                        end
                    }
                }
            }
        end
    end

    YAML.add_ruby_type( 'flexhash' ) { |type, val|
        if Array === val
            p = FlexHash.new
            val.each { |v|
                if Hash === v
                    p.concat( v.to_a )		# Convert the map to a sequence
                else
                    p << [ v, nil ]
                end
            }
            p
        else
            raise YAML::Error, "Invalid !ruby/flexhash: " + val.inspect
        end
    }
end

#
# Structs: export as a !map
#
class Struct
    def is_complex_yaml?
        true
    end
	def to_yaml( opts = {} )
		YAML::quick_emit( self.object_id, opts ) { |out|
			#
			# Basic struct is passed as a YAML map
			#
			struct_name = self.class.name.gsub( "Struct:", "" )
            out.map( "!ruby/struct#{struct_name}" ) { |map|
				self.members.each { |m|
                    map.add( m, self[m] )
				}
			}
		}
	end
end

YAML.add_ruby_type( 'struct' ) { |type, val|
	if Hash === val
        struct_type = nil

		#
		# Use existing Struct if it exists
		#
		begin
			struct_name, struct_type = YAML.read_type_class( type, Struct )
		rescue NameError
		end
		if not struct_type
            struct_def = [ type.split( ':', 4 ).last ]
			struct_type = Struct.new( *struct_def.concat( val.keys.collect { |k| k.intern } ) ) 
		end

		#
		# Set the Struct properties
		#
		st = struct_type.new
		st.members.each { |m|
			st.send( "#{m}=", val[m] )
		}
		st
	else
		raise YAML::Error, "Invalid Ruby Struct: " + val.inspect
	end
}

#
# Sequences: Array#to_yaml
#
class Array
    def is_complex_yaml?
        true
    end
    def to_yaml_type
        if self.class == Array 
            "!seq"
        else
            "!ruby/array:#{self.class}"
        end
    end
	def to_yaml( opts = {} )
		opts[:DocType] = self.class if Hash === opts
		YAML::quick_emit( self.object_id, opts ) { |out|
            array_type = to_yaml_type 
            if not out.options[:ExplicitTypes] and array_type == "!seq"
                array_type = ""
            end
			
            out.seq( array_type ) { |seq|
                seq.concat( self )
            }
		}
	end
end

array_proc = Proc.new { |type, val|
    if Array === val
        type, obj_class = YAML.read_type_class( type, Array )
        if obj_class != Array
            o = obj_class.new
            o.concat( val )
            val = o
        end
        val
    else
        val.to_a
    end
}
YAML.add_builtin_type( 'seq', &array_proc )
YAML.add_ruby_type( 'array', &array_proc ) 

#
# Exception#to_yaml
#
class Exception
    def is_complex_yaml?
        true
    end
    def to_yaml_type
        "!ruby/exception:#{self.class}"
    end
	def to_yaml( opts = {} )
		YAML::quick_emit( self.object_id, opts ) { |out|
            out.map( self.to_yaml_type ) { |map|
                map.add( 'message', self.message )
				to_yaml_properties.each { |m|
                    map.add( m[1..-1], instance_eval( m ) )
                }
            }
		}
	end
end

YAML.add_ruby_type( 'exception' ) { |type, val|
    type, obj_class = YAML.read_type_class( type, Exception )
    o = YAML.object_maker( obj_class, { 'mesg' => val.delete( 'message' ) }, true )
    val.each_pair { |k,v|
		o.instance_eval "@#{k} = v"
	}
	o
}


#
# String#to_yaml
#
class String
    def is_complex_yaml?
        ( self =~ /\n.+/ ? true : false )
    end
    def is_binary_data?
        ( self.count( "^ -~", "^\r\n" ) / self.size > 0.3 || self.count( "\x00" ) > 0 )
    end
	def to_yaml( opts = {} )
        complex = false
        if self.is_complex_yaml?
            complex = true
        elsif opts[:BestWidth].to_i > 0
            if self.length > opts[:BestWidth] and opts[:UseFold]
                complex = true
            end
        end
		YAML::quick_emit( complex ? self.object_id : nil, opts ) { |out|
            if complex
                if self.is_binary_data?
                    out.binary_base64( self )
                elsif self =~ /^ |#{YAML::ESCAPE_CHAR}| $/
                    complex = false
                else
                    out.node_text( self )
                end
            end
            if not complex
                ostr = 	if out.options[:KeepValue]
                            self
                        elsif empty?
                            "''"
                        elsif self =~ /^[^#{YAML::WORD_CHAR}]|#{YAML::ESCAPE_CHAR}|[#{YAML::SPACE_INDICATORS}]( |$)| $|\n|\'/
                            "\"#{YAML.escape( self )}\"" 
                        elsif YAML.detect_implicit( self ) != 'str'
                            "\"#{YAML.escape( self )}\"" 
                        else
                            self
                        end
                out.simple( ostr )
            end
		}
	end
end

YAML.add_builtin_type( 'str' ) { |type,val| val.to_s }
YAML.add_builtin_type( 'binary' ) { |type,val|
	enctype = "m"
	if String === val
		val.gsub( /\s+/, '' ).unpack( enctype )[0]
	else
		raise YAML::Error, "Binary data must be represented by a string: " + val.inspect
	end
}

#
# Symbol#to_yaml
#
class Symbol
    def is_complex_yaml?
        false
    end
	def to_yaml( opts = {} )
		YAML::quick_emit( nil, opts ) { |out|
			out << "!ruby/sym "
			self.id2name.to_yaml( :Emitter => out )
		}
	end
end

symbol_proc = Proc.new { |type, val|
	if String === val
		val.intern
	else
		raise YAML::Error, "Invalid Symbol: " + val.inspect
	end
}
YAML.add_ruby_type( 'symbol', &symbol_proc ) 
YAML.add_ruby_type( 'sym', &symbol_proc ) 

#
# Range#to_yaml
#
class Range
    def is_complex_yaml?
        false
    end
	def to_yaml( opts = {} )
		YAML::quick_emit( nil, opts ) { |out|
			out << "!ruby/range " 
			self.inspect.to_yaml( :Emitter => out )
		}
	end
end

YAML.add_ruby_type( 'range' ) { |type, val|
	if String === val and val =~ /^(.*[^.])(\.{2,3})([^.].*)$/
        r1, rdots, r2 = $1, $2, $3
		Range.new( YAML.try_implicit( r1 ), YAML.try_implicit( r2 ), rdots.length == 3 )
	elsif Hash === val
		Range.new( val['begin'], val['end'], val['exclude_end?'] )
	else
		raise YAML::Error, "Invalid Range: " + val.inspect
	end
}

#
# Make an RegExp
#
class Regexp
    def is_complex_yaml?
        false
    end
	def to_yaml( opts = {} )
		YAML::quick_emit( nil, opts ) { |out|
			out << "!ruby/regexp "
			self.inspect.to_yaml( :Emitter => out )
		}
	end
end

regexp_proc = Proc.new { |type, val|
	if String === val and val =~ /^\/(.*)\/([mix]*)$/
		val = { 'REGEXP' => $1, 'MODIFIERS' => $2 }
	end
	if Hash === val
		mods = nil
		unless val['MODIFIERS'].to_s.empty?
			mods = 0x00
			if val['MODIFIERS'].include?( 'x' )
				mods |= Regexp::EXTENDED
			elsif val['MODIFIERS'].include?( 'i' )
				mods |= Regexp::IGNORECASE
			elsif val['MODIFIERS'].include?( 'm' )
				mods |= Regexp::POSIXLINE
			end
		end
		Regexp::compile( val['REGEXP'], mods )
	else
		raise YAML::Error, "Invalid Regular expression: " + val.inspect
	end
}
YAML.add_domain_type( "perl.yaml.org,2002", /^regexp/, &regexp_proc )
YAML.add_ruby_type( 'regexp', &regexp_proc )

#
# Emit a Time object as an ISO 8601 timestamp
#
class Time
    def is_complex_yaml?
        false
    end
	def to_yaml( opts = {} )
		YAML::quick_emit( nil, opts ) { |out|
            tz = "Z"
            # from the tidy Tobias Peters <t-peters@gmx.de> Thanks!
            unless self.utc?
                utc_same_instant = self.dup.utc
                utc_same_writing = Time.utc(year,month,day,hour,min,sec,usec)
                difference_to_utc = utc_same_writing - utc_same_instant
                if (difference_to_utc < 0) 
                    difference_sign = '-'
                    absolute_difference = -difference_to_utc
                else
                    difference_sign = '+'
                    absolute_difference = difference_to_utc
                end
                difference_minutes = (absolute_difference/60).round
                tz = "%s%02d:%02d" % [ difference_sign, difference_minutes / 60, difference_minutes % 60]
            end
            ( self.strftime( "%Y-%m-%d %H:%M:%S." ) +
                "%06d %s" % [usec, tz] ).
                to_yaml( :Emitter => out, :KeepValue => true )
		}
	end
end

YAML.add_builtin_type( 'time#ymd' ) { |type, val|
	if val =~ /\A(\d{4})\-(\d{1,2})\-(\d{1,2})\Z/
		Date.new($1.to_i, $2.to_i, $3.to_i)
    else
        raise YAML::TypeError, "Invalid !time string: " + val.inspect
    end
}

#
# Emit a Date object as a simple implicit
#
class Date
    def is_complex_yaml?
        false
    end
	def to_yaml( opts = {} )
		opts[:KeepValue] = true
		self.to_s.to_yaml( opts )
	end
end

#
# Send Integer, Booleans, NilClass to String
#
class Numeric
    def is_complex_yaml?
        false
    end
	def to_yaml( opts = {} )
		str = self.to_s
		if str == "Infinity"
			str = ".Inf"
		elsif str == "-Infinity"
			str = "-.Inf"
		elsif str == "NaN"
			str = ".NaN"
		end
		opts[:KeepValue] = true
		str.to_yaml( opts )
	end
end

YAML.add_builtin_type( 'float' ) { |type, val|
    if val =~ /\A[-+]?[\d][\d,]*\.[\d,]*[eE][-+][0-9]+\Z/						# Float (exponential)
        $&.tr( ',', '' ).to_f
    elsif val =~ /\A[-+]?[\d][\d,]*\.[\d,]*\Z/									# Float (fixed)
        $&.tr( ',', '' ).to_f
    elsif val =~ /\A([-+]?)\.(inf|Inf|INF)\Z/										# Float (english)
        ( $1 == "-" ? -1.0/0.0 : 1.0/0.0 )
    elsif val =~ /\A\.(nan|NaN|NAN)\Z/
        0.0/0.0
    elsif type == :Implicit
        :InvalidType
    else
        val.to_f
    end
}

YAML.add_builtin_type( 'int' ) { |type, val|
    if val =~ /\A[-+]?0[0-7,]+\Z/												# Integer (octal)
        $&.oct
    elsif val =~ /\A[-+]?0x[0-9a-fA-F,]+\Z/										# Integer (hex)
        $&.hex
    elsif val =~ /\A[-+]?\d[\d,]*\Z/												# Integer (canonical)
        $&.tr( ',', '' ).to_i
    elsif val =~ /\A([-+]?)(\d[\d,]*(?::[0-5]?[0-9])+)\Z/
        sign = ( $1 == '-' ? -1 : 1 )
        digits = $2.split( /:/ ).collect { |x| x.to_i }
        val = 0; digits.each { |x| val = ( val * 60 ) + x }; val *= sign
    elsif type == :Implicit
        :InvalidType
    else
        val.to_i
    end
}

class TrueClass
    def is_complex_yaml?
        false
    end
	def to_yaml( opts = {} )
		opts[:KeepValue] = true
		"true".to_yaml( opts )
	end
end

class FalseClass
    def is_complex_yaml?
        false
    end
	def to_yaml( opts = {} )
		opts[:KeepValue] = true
		"false".to_yaml( opts )
	end
end

YAML.add_builtin_type( 'bool' ) { |type, val|
    if val =~ /\A(\+|true|True|TRUE|yes|Yes|YES|on|On|ON)\Z/
        true
    elsif val =~ /\A(\-|false|False|FALSE|no|No|NO|off|Off|OFF)\Z/
        false
    elsif type == :Implicit
        :InvalidType
    else
        raise YAML::TypeError, "Invalid !bool string: " + val.inspect
    end
}

class NilClass 
    def is_complex_yaml?
        false
    end
	def to_yaml( opts = {} )
		opts[:KeepValue] = true
		"".to_yaml( opts )
	end
end

YAML.add_builtin_type( 'null' ) { |type, val| 
    if val =~ /\A(\~|null|Null|NULL)\Z/
        nil
    elsif val.empty?
        nil
    elsif type == :Implicit
        :InvalidType
    else
        raise YAML::TypeError, "Invalid !null string: " + val.inspect
    end
}

