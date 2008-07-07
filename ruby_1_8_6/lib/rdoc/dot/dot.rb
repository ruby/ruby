module DOT

    # these glogal vars are used to make nice graph source
    $tab = '    '
    $tab2 = $tab * 2

    # if we don't like 4 spaces, we can change it any time
    def change_tab( t )
        $tab = t
        $tab2 = t * 2
    end

    # options for node declaration
    NODE_OPTS = [
        'bgcolor',
        'color',
        'fontcolor',
        'fontname',
        'fontsize',
        'height',
        'width',
        'label',
        'layer',
        'rank',
        'shape',
        'shapefile',
        'style',
        'URL',
    ]

    # options for edge declaration
    EDGE_OPTS = [
        'color',
        'decorate',
        'dir',
        'fontcolor',
        'fontname',
        'fontsize',
        'id',
        'label',
        'layer',
        'lhead',
        'ltail',
        'minlen',
        'style',
        'weight'
    ]

    # options for graph declaration
    GRAPH_OPTS = [
        'bgcolor',
        'center',
        'clusterrank',
        'color',
        'compound',
        'concentrate',
        'fillcolor',
        'fontcolor',
        'fontname',
        'fontsize',
        'label',
        'layerseq',
        'margin',
        'mclimit',
        'nodesep',
        'nslimit',
        'ordering',
        'orientation',
        'page',
        'rank',
        'rankdir',
        'ranksep',
        'ratio',
        'size',
        'style',
        'URL'
    ]

    # a root class for any element in dot notation
    class DOTSimpleElement
        attr_accessor :name

        def initialize( params = {} )
            @label = params['name'] ? params['name'] : ''
        end

        def to_s
            @name
        end
    end

    # an element that has options ( node, edge or graph )
    class DOTElement < DOTSimpleElement
        #attr_reader :parent
        attr_accessor :name, :options

        def initialize( params = {}, option_list = [] )
            super( params )
            @name = params['name'] ? params['name'] : nil
            @parent = params['parent'] ? params['parent'] : nil
            @options = {}
            option_list.each{ |i|
                @options[i] = params[i] if params[i]
            }
            @options['label'] ||= @name if @name != 'node'
        end

        def each_option
            @options.each{ |i| yield i }
        end

        def each_option_pair
            @options.each_pair{ |key, val| yield key, val }
        end

        #def parent=( thing )
        #    @parent.delete( self ) if defined?( @parent ) and @parent
        #    @parent = thing
        #end
    end


    # this is used when we build nodes that have shape=record
    # ports don't have options :)
    class DOTPort < DOTSimpleElement
        attr_accessor :label

        def initialize( params = {} )
            super( params )
            @name = params['label'] ? params['label'] : ''
        end
        def to_s
            ( @name && @name != "" ? "<#{@name}>" : "" ) + "#{@label}"
        end
    end

    # node element
    class DOTNode < DOTElement

        def initialize( params = {}, option_list = NODE_OPTS )
            super( params, option_list )
            @ports = params['ports'] ? params['ports'] : []
        end

        def each_port
            @ports.each{ |i| yield i }
        end

        def << ( thing )
            @ports << thing
        end

        def push ( thing )
            @ports.push( thing )
        end

        def pop
            @ports.pop
        end

        def to_s( t = '' )

            label = @options['shape'] != 'record' && @ports.length == 0 ?
                @options['label'] ?
                    t + $tab + "label = \"#{@options['label']}\"\n" :
                    '' :
                t + $tab + 'label = "' + " \\\n" +
                t + $tab2 + "#{@options['label']}| \\\n" +
                @ports.collect{ |i|
                    t + $tab2 + i.to_s
                }.join( "| \\\n" ) + " \\\n" +
                t + $tab + '"' + "\n"

            t + "#{@name} [\n" +
            @options.to_a.collect{ |i|
                i[1] && i[0] != 'label' ?
                    t + $tab + "#{i[0]} = #{i[1]}" : nil
            }.compact.join( ",\n" ) + ( label != '' ? ",\n" : "\n" ) +
            label +
            t + "]\n"
        end
    end

    # subgraph element is the same to graph, but has another header in dot
    # notation
    class DOTSubgraph < DOTElement

        def initialize( params = {}, option_list = GRAPH_OPTS )
            super( params, option_list )
            @nodes = params['nodes'] ? params['nodes'] : []
            @dot_string = 'subgraph'
        end

        def each_node
            @nodes.each{ |i| yield i }
        end

        def << ( thing )
            @nodes << thing
        end

        def push( thing )
            @nodes.push( thing )
        end

        def pop
            @nodes.pop
        end

        def to_s( t = '' )
          hdr = t + "#{@dot_string} #{@name} {\n"

          options = @options.to_a.collect{ |name, val|
            val && name != 'label' ?
            t + $tab + "#{name} = #{val}" :
              name ? t + $tab + "#{name} = \"#{val}\"" : nil
          }.compact.join( "\n" ) + "\n"

          nodes = @nodes.collect{ |i|
            i.to_s( t + $tab )
          }.join( "\n" ) + "\n"
          hdr + options + nodes + t + "}\n"
        end
    end

    # this is graph
    class DOTDigraph < DOTSubgraph
        def initialize( params = {}, option_list = GRAPH_OPTS )
            super( params, option_list )
            @dot_string = 'digraph'
        end
    end

    # this is edge
    class DOTEdge < DOTElement
        attr_accessor :from, :to
        def initialize( params = {}, option_list = EDGE_OPTS )
            super( params, option_list )
            @from = params['from'] ? params['from'] : nil
            @to = params['to'] ? params['to'] : nil
        end

        def to_s( t = '' )
            t + "#{@from} -> #{to} [\n" +
            @options.to_a.collect{ |i|
                i[1] && i[0] != 'label' ?
                    t + $tab + "#{i[0]} = #{i[1]}" :
                    i[1] ? t + $tab + "#{i[0]} = \"#{i[1]}\"" : nil
            }.compact.join( "\n" ) + "\n" + t + "]\n"
        end
    end
end



