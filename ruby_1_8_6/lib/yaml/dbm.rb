require 'yaml'
require 'dbm'
#
# YAML + DBM = YDBM
# - Same interface as DBM class
#
module YAML

class DBM < ::DBM
    VERSION = "0.1"
    def []( key )
        fetch( key )
    end
    def []=( key, val )
        store( key, val )
    end
    def fetch( keystr, ifnone = nil )
        begin
            val = super( keystr )
            return YAML::load( val ) if String === val
        rescue IndexError
        end
        if block_given?
            yield keystr
        else
            ifnone
        end
    end
    def index( keystr )
        super( keystr.to_yaml )
    end
    def values_at( *keys )
        keys.collect { |k| fetch( k ) }
    end
    def delete( key )
        v = super( key )
        if String === v
            v = YAML::load( v ) 
        end
        v
    end
    def delete_if
        del_keys = keys.dup
        del_keys.delete_if { |k| yield( k, fetch( k ) ) == false }
        del_keys.each { |k| delete( k ) } 
        self
    end
    def reject
        hsh = self.to_hash
        hsh.reject { |k,v| yield k, v }
    end
    def each_pair
        keys.each { |k| yield k, fetch( k ) }
        self
    end
    def each_value
        super { |v| yield YAML::load( v ) }
        self
    end
    def values
        super.collect { |v| YAML::load( v ) }
    end
    def has_value?( val )
        each_value { |v| return true if v == val }
        return false
    end
    def invert
        h = {}
        keys.each { |k| h[ self.fetch( k ) ] = k }
        h
    end
    def replace( hsh )
        clear
        update( hsh )
    end
    def shift
        a = super
        a[1] = YAML::load( a[1] ) if a
        a
    end
    def select( *keys )
        if block_given?
            self.keys.collect { |k| v = self[k]; [k, v] if yield k, v }.compact
        else
            values_at( *keys )
        end
    end
    def store( key, val )
        super( key, val.to_yaml )
        val
    end
    def update( hsh )
        hsh.keys.each do |k|
            self.store( k, hsh.fetch( k ) )
        end
        self
    end
    def to_a
        a = []
        keys.each { |k| a.push [ k, self.fetch( k ) ] }
        a
    end
    def to_hash
        h = {}
        keys.each { |k| h[ k ] = self.fetch( k ) }
        h
    end
    alias :each :each_pair
end

end
