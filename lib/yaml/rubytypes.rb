# -*- mode: ruby; ruby-indent-level: 4; tab-width: 4 -*- vim: sw=4 ts=4
require 'date'
#
# Type conversions
#

class Class
	def to_yaml( opts = {} )
		raise TypeError, "can't dump anonymous class %s" % self.class
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
                    map.add( m[1..-1], instance_variable_get( m ) )
                }
            }
		}
	end
end

YAML.add_ruby_type( /^object/ ) { |type, val|
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
            if not out.options(:ExplicitTypes) and hash_type == "!map"
                hash_type = ""
            end
            out.map( hash_type ) { |map|
				#
				# Sort the hash
				#
                if out.options(:SortKeys)
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
YAML.add_ruby_type( /^hash/, &hash_proc ) 

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
			struct_name = self.class.name.gsub( "Struct::", "" )
            out.map( "!ruby/struct:#{struct_name}" ) { |map|
				self.members.each { |m|
                    map.add( m, self[m] )
				}
				self.to_yaml_properties.each { |m|
                    map.add( m, instance_variable_get( m ) )
                }
			}
		}
	end
end

YAML.add_ruby_type( /^struct/ ) { |type, val|
	if Hash === val
        struct_type = nil

		#
		# Use existing Struct if it exists
		#
        props = {}
        val.delete_if { |k,v| props[k] = v if k =~ /^@/ }
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
		st = YAML::object_maker( struct_type, {} )
		st.members.each { |m|
			st.send( "#{m}=", val[m] )
		}
        props.each { |k,v|
            st.instance_variable_set(k, v)
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
            if not out.options(:ExplicitTypes) and array_type == "!seq"
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
YAML.add_ruby_type( /^array/, &array_proc ) 

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
                    map.add( m[1..-1], instance_variable_get( m ) )
                }
            }
		}
	end
end

YAML.add_ruby_type( /^exception/ ) { |type, val|
    type, obj_class = YAML.read_type_class( type, Exception )
    o = YAML.object_maker( obj_class, { 'mesg' => val.delete( 'message' ) } )
    val.each_pair { |k,v|
		o.instance_variable_set("@#{k}", v)
	}
	o
}


#
# String#to_yaml
#
class String
    def is_complex_yaml?
        to_yaml_fold or not to_yaml_properties.empty? or self =~ /\n.+/
    end
    def is_binary_data?
        ( self.count( "^ -~", "^\r\n" ) / self.size > 0.3 || self.count( "\x00" ) > 0 )
    end
    def to_yaml_type
        "!ruby/string#{ ":#{ self.class }" if self.class != ::String }"
    end
    def to_yaml_fold
        nil
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
                if not to_yaml_properties.empty?
                    out.map( self.to_yaml_type ) { |map|
                        map.add( 'str', "#{self}" )
                        to_yaml_properties.each { |m|
                            map.add( m, instance_variable_get( m ) )
                        }
                    }
                elsif self.is_binary_data?
                    out.binary_base64( self )
                elsif self =~ /#{YAML::ESCAPE_CHAR}/
                    out.node_text( self, '"' )
                else
                    out.node_text( self, to_yaml_fold )
                end
            else
                ostr = 	if out.options(:KeepValue)
                            self
                        elsif empty?
                            "''"
                        elsif self =~ /^[^#{YAML::WORD_CHAR}\/]| \#|#{YAML::ESCAPE_CHAR}|[#{YAML::SPACE_INDICATORS}]( |$)| $|\n|\'/
                            out.node_text( self, '"' ); nil
                        elsif YAML.detect_implicit( self ) != 'str'
                            out.node_text( self, '"' ); nil
                        else
                            self
                        end
                out.simple( ostr ) unless ostr.nil?
            end
		}
	end
end

YAML.add_ruby_type( /^string/ ) { |type, val|
    type, obj_class = YAML.read_type_class( type, ::String )
	if Hash === val
        s = YAML::object_maker( obj_class, {} )
        # Thank you, NaHi
        String.instance_method(:initialize).
              bind(s).
              call( val.delete( 'str' ) )
        val.each { |k,v| s.instance_variable_set( k, v ) }
        s
	else
		raise YAML::Error, "Invalid String: " + val.inspect
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
			out << ":"
			self.id2name.to_yaml( :Emitter => out )
		}
	end
end

symbol_proc = Proc.new { |type, val|
	if String === val
        val = YAML::load( "--- #{val}") if val =~ /^["'].*['"]$/
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
        true
    end
    def to_yaml_type
        "!ruby/range#{ if self.class != ::Range; ":#{ self.class }"; end }"
    end
	def to_yaml( opts = {} )
		YAML::quick_emit( self.object_id, opts ) { |out|
            if self.begin.is_complex_yaml? or self.begin.respond_to? :to_str or
              self.end.is_complex_yaml? or self.end.respond_to? :to_str or
              not to_yaml_properties.empty?
                out.map( to_yaml_type ) { |map|
                    map.add( 'begin', self.begin )
                    map.add( 'end', self.end )
                    map.add( 'excl', self.exclude_end? )
                    to_yaml_properties.each { |m|
                        map.add( m, instance_variable_get( m ) )
                    }
                }
            else
                out << "#{ to_yaml_type } '" 
                self.begin.to_yaml(:Emitter => out)
                out << ( self.exclude_end? ? "..." : ".." )
                self.end.to_yaml(:Emitter => out)
                out << "'"
            end
		}
	end
end

YAML.add_ruby_type( /^range/ ) { |type, val|
    type, obj_class = YAML.read_type_class( type, ::Range )
    inr = %r'(\w+|[+-]?\d+(?:\.\d+)?(?:e[+-]\d+)?|"(?:[^\\"]|\\.)*")'
    opts = {}
	if String === val and val =~ /^#{inr}(\.{2,3})#{inr}$/o
        r1, rdots, r2 = $1, $2, $3
        opts = {
            'begin' => YAML.load( "--- #{r1}" ),
            'end' => YAML.load( "--- #{r2}" ),
            'excl' => rdots.length == 3
        }
        val = {}
    elsif Hash === val
        opts['begin'] = val.delete('begin')
        opts['end'] = val.delete('end')
        opts['excl'] = val.delete('excl')
    end
	if Hash === opts
        r = YAML::object_maker( obj_class, {} )
        # Thank you, NaHi
        Range.instance_method(:initialize).
              bind(r).
              call( opts['begin'], opts['end'], opts['excl'] )
        val.each { |k,v| r.instance_variable_set( k, v ) }
        r
	else
		raise YAML::Error, "Invalid Range: " + val.inspect
	end
}

#
# Make an Regexp
#
class Regexp
    def is_complex_yaml?
        self.class != Regexp or not to_yaml_properties.empty?
    end
    def to_yaml_type
        "!ruby/regexp#{ if self.class != ::Regexp; ":#{ self.class }"; end }"
    end
	def to_yaml( opts = {} )
		YAML::quick_emit( nil, opts ) { |out|
            if self.is_complex_yaml?
                out.map( self.to_yaml_type ) { |map|
                    src = self.inspect
                    if src =~ /\A\/(.*)\/([a-z]*)\Z/
                        map.add( 'regexp', $1 )
                        map.add( 'mods', $2 )
                    else
		                raise YAML::Error, "Invalid Regular expression: " + src
                    end
                    to_yaml_properties.each { |m|
                        map.add( m, instance_variable_get( m ) )
                    }
                }
            else
                out << "#{ to_yaml_type } "
                self.inspect.to_yaml( :Emitter => out )
            end
		}
	end
end

regexp_proc = Proc.new { |type, val|
    type, obj_class = YAML.read_type_class( type, ::Regexp )
	if String === val and val =~ /^\/(.*)\/([mix]*)$/
		val = { 'regexp' => $1, 'mods' => $2 }
	end
	if Hash === val
		mods = nil
		unless val['mods'].to_s.empty?
			mods = 0x00
			mods |= Regexp::EXTENDED if val['mods'].include?( 'x' )
			mods |= Regexp::IGNORECASE if val['mods'].include?( 'i' )
			mods |= Regexp::MULTILINE if val['mods'].include?( 'm' )
		end
        val.delete( 'mods' )
        r = YAML::object_maker( obj_class, {} )
        Regexp.instance_method(:initialize).
              bind(r).
              call( val.delete( 'regexp' ), mods )
        val.each { |k,v| r.instance_variable_set( k, v ) }
        r
	else
		raise YAML::Error, "Invalid Regular expression: " + val.inspect
	end
}
YAML.add_domain_type( "perl.yaml.org,2002", /^regexp/, &regexp_proc )
YAML.add_ruby_type( /^regexp/, &regexp_proc )

#
# Emit a Time object as an ISO 8601 timestamp
#
class Time
    def is_complex_yaml?
        self.class != Time or not to_yaml_properties.empty?
    end
    def to_yaml_type
        "!ruby/time#{ if self.class != ::Time; ":#{ self.class }"; end }"
    end
	def to_yaml( opts = {} )
		YAML::quick_emit( nil, opts ) { |out|
            if self.is_complex_yaml?
                out.map( self.to_yaml_type ) { |map|
                    map.add( 'at', ::Time.at( self ) )
                    to_yaml_properties.each { |m|
                        map.add( m, instance_variable_get( m ) )
                    }
                }
            else
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
                standard = self.strftime( "%Y-%m-%d %H:%M:%S" )
                standard += ".%06d" % [usec] if usec.nonzero?
                standard += " %s" % [tz]
                standard.to_yaml( :Emitter => out, :KeepValue => true )
            end
		}
	end
end

YAML.add_ruby_type( /^time/ ) { |type, val|
    type, obj_class = YAML.read_type_class( type, ::Time )
	if Hash === val
        t = obj_class.at( val.delete( 'at' ) )
        val.each { |k,v| t.instance_variable_set( k, v ) }
        t
	else
		raise YAML::Error, "Invalid Time: " + val.inspect
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

class NilClass 
    def is_complex_yaml?
        false
    end
	def to_yaml( opts = {} )
		opts[:KeepValue] = true
		"".to_yaml( opts )
	end
end

