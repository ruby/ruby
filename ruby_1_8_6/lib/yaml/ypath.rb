#
# YAML::YPath
#

module YAML

    class YPath
        attr_accessor :segments, :predicates, :flags
        def initialize( str )
            @segments = []
            @predicates = []
            @flags = nil
            while str =~ /^\/?(\/|[^\/\[]+)(?:\[([^\]]+)\])?/
                @segments.push $1
                @predicates.push $2
                str = $'
            end
            unless str.to_s.empty?
                @segments += str.split( "/" )
            end
            if @segments.length == 0
                @segments.push "."
            end
        end
        def YPath.each_path( str )
            #
            # Find choices
            #
            paths = []
            str = "(#{ str })"
            while str.sub!( /\(([^()]+)\)/, "\n#{ paths.length }\n" )
                paths.push $1.split( '|' )
            end

            #
            # Construct all possible paths
            #
            all = [ str ]
            ( paths.length - 1 ).downto( 0 ) do |i|
                all = all.collect do |a|
                    paths[i].collect do |p|
                        a.gsub( /\n#{ i }\n/, p )
                    end
                end.flatten.uniq
            end
            all.collect do |path|
                yield YPath.new( path )
            end
        end
    end

end
