# A wonderful hack by to draw package diagrams using the dot package.
# Originally written by  Jah, team Enticla.
#
# You must have the V1.7 or later in your path
# http://www.research.att.com/sw/tools/graphviz/

require 'rdoc/dot'

module RDoc

  ##
  # Draw a set of diagrams representing the modules and classes in the
  # system. We draw one diagram for each file, and one for each toplevel
  # class or module. This means there will be overlap. However, it also
  # means that you'll get better context for objects.
  #
  # To use, simply
  #
  #   d = Diagram.new(info)   # pass in collection of top level infos
  #   d.draw
  #
  # The results will be written to the +dot+ subdirectory. The process
  # also sets the +diagram+ attribute in each object it graphs to
  # the name of the file containing the image. This can be used
  # by output generators to insert images.

  class Diagram

    FONT = "Arial"

    DOT_PATH = "dot"

    ##
    # Pass in the set of top level objects. The method also creates the
    # subdirectory to hold the images

    def initialize(info, options)
      @info = info
      @options = options
      @counter = 0
      FileUtils.mkdir_p(DOT_PATH)
      @diagram_cache = {}
    end

    ##
    # Draw the diagrams. We traverse the files, drawing a diagram for each. We
    # also traverse each top-level class and module in that file drawing a
    # diagram for these too.

    def draw
      unless @options.quiet
        $stderr.print "Diagrams: "
        $stderr.flush
      end

      @info.each_with_index do |i, file_count|
        @done_modules = {}
        @local_names = find_names(i)
        @global_names = []
        @global_graph = graph = DOT::Digraph.new('name' => 'TopLevel',
                                                 'fontname' => FONT,
                                                 'fontsize' => '8',
                                                 'bgcolor'  => 'lightcyan1',
                                                 'compound' => 'true')

        # it's a little hack %) i'm too lazy to create a separate class
        # for default node
        graph << DOT::Node.new('name' => 'node',
                               'fontname' => FONT,
                               'color' => 'black',
                               'fontsize' => 8)

        i.modules.each do |mod|
          draw_module(mod, graph, true, i.file_relative_name)
        end
        add_classes(i, graph, i.file_relative_name)

        i.diagram = convert_to_png("f_#{file_count}", graph)

        # now go through and document each top level class and
        # module independently
        i.modules.each_with_index do |mod, count|
          @done_modules = {}
          @local_names = find_names(mod)
          @global_names = []

          @global_graph = graph = DOT::Digraph.new('name' => 'TopLevel',
                                                   'fontname' => FONT,
                                                   'fontsize' => '8',
                                                   'bgcolor'  => 'lightcyan1',
                                                   'compound' => 'true')

          graph << DOT::Node.new('name' => 'node',
                                 'fontname' => FONT,
                                 'color' => 'black',
                                 'fontsize' => 8)
          draw_module(mod, graph, true)
          mod.diagram = convert_to_png("m_#{file_count}_#{count}",
                                       graph)
        end
      end
      $stderr.puts unless @options.quiet
    end

    private

    def find_names(mod)
      return [mod.full_name] + mod.classes.collect{|cl| cl.full_name} +
        mod.modules.collect{|m| find_names(m)}.flatten
    end

    def find_full_name(name, mod)
      full_name = name.dup
      return full_name if @local_names.include?(full_name)
      mod_path = mod.full_name.split('::')[0..-2]
      unless mod_path.nil?
        until mod_path.empty?
          full_name = mod_path.pop + '::' + full_name
          return full_name if @local_names.include?(full_name)
        end
      end
      return name
    end

    def draw_module(mod, graph, toplevel = false, file = nil)
      return if  @done_modules[mod.full_name] and not toplevel

      @counter += 1
      url = mod.http_url("classes")
      m = DOT::Subgraph.new('name' => "cluster_#{mod.full_name.gsub( /:/,'_' )}",
                            'label' => mod.name,
                            'fontname' => FONT,
                            'color' => 'blue',
                            'style' => 'filled',
                            'URL'   => %{"#{url}"},
                            'fillcolor' => toplevel ? 'palegreen1' : 'palegreen3')

      @done_modules[mod.full_name] = m
      add_classes(mod, m, file)
      graph << m

      unless mod.includes.empty?
        mod.includes.each do |inc|
          m_full_name = find_full_name(inc.name, mod)
          if @local_names.include?(m_full_name)
            @global_graph << DOT::Edge.new('from' => "#{m_full_name.gsub( /:/,'_' )}",
                                           'to' => "#{mod.full_name.gsub( /:/,'_' )}",
                                           'ltail' => "cluster_#{m_full_name.gsub( /:/,'_' )}",
                                           'lhead' => "cluster_#{mod.full_name.gsub( /:/,'_' )}")
          else
            unless @global_names.include?(m_full_name)
              path = m_full_name.split("::")
              url = File.join('classes', *path) + ".html"
              @global_graph << DOT::Node.new('name' => "#{m_full_name.gsub( /:/,'_' )}",
                                             'shape' => 'box',
                                             'label' => "#{m_full_name}",
                                             'URL'   => %{"#{url}"})
              @global_names << m_full_name
            end
            @global_graph << DOT::Edge.new('from' => "#{m_full_name.gsub( /:/,'_' )}",
                                           'to' => "#{mod.full_name.gsub( /:/,'_' )}",
                                           'lhead' => "cluster_#{mod.full_name.gsub( /:/,'_' )}")
          end
        end
      end
    end

    def add_classes(container, graph, file = nil )

      use_fileboxes = @options.fileboxes

      files = {}

      # create dummy node (needed if empty and for module includes)
      if container.full_name
        graph << DOT::Node.new('name'     => "#{container.full_name.gsub( /:/,'_' )}",
                               'label'    => "",
                               'width'  => (container.classes.empty? and
                                            container.modules.empty?) ?
                               '0.75' : '0.01',
                               'height' => '0.01',
                               'shape' => 'plaintext')
      end

      container.classes.each_with_index do |cl, cl_index|
        last_file = cl.in_files[-1].file_relative_name

        if use_fileboxes && !files.include?(last_file)
          @counter += 1
          files[last_file] =
            DOT::Subgraph.new('name'     => "cluster_#{@counter}",
                                 'label'    => "#{last_file}",
                                 'fontname' => FONT,
                                 'color'=>
                                 last_file == file ? 'red' : 'black')
        end

        next if cl.name == 'Object' || cl.name[0,2] == "<<"

        url = cl.http_url("classes")

        label = cl.name.dup
        if use_fileboxes && cl.in_files.length > 1
          label <<  '\n[' +
                        cl.in_files.collect {|i|
                             i.file_relative_name
                        }.sort.join( '\n' ) +
                    ']'
        end

        attrs = {
          'name' => "#{cl.full_name.gsub( /:/, '_' )}",
          'fontcolor' => 'black',
          'style'=>'filled',
          'color'=>'palegoldenrod',
          'label' => label,
          'shape' => 'ellipse',
          'URL'   => %{"#{url}"}
        }

        c = DOT::Node.new(attrs)

        if use_fileboxes
          files[last_file].push c
        else
          graph << c
        end
      end

      if use_fileboxes
        files.each_value do |val|
          graph << val
        end
      end

      unless container.classes.empty?
        container.classes.each_with_index do |cl, cl_index|
          cl.includes.each do |m|
            m_full_name = find_full_name(m.name, cl)
            if @local_names.include?(m_full_name)
              @global_graph << DOT::Edge.new('from' => "#{m_full_name.gsub( /:/,'_' )}",
                                             'to' => "#{cl.full_name.gsub( /:/,'_' )}",
                                             'ltail' => "cluster_#{m_full_name.gsub( /:/,'_' )}")
            else
              unless @global_names.include?(m_full_name)
                path = m_full_name.split("::")
                url = File.join('classes', *path) + ".html"
                @global_graph << DOT::Node.new('name' => "#{m_full_name.gsub( /:/,'_' )}",
                                               'shape' => 'box',
                                               'label' => "#{m_full_name}",
                                               'URL'   => %{"#{url}"})
                @global_names << m_full_name
              end
              @global_graph << DOT::Edge.new('from' => "#{m_full_name.gsub( /:/,'_' )}",
                                             'to' => "#{cl.full_name.gsub( /:/, '_')}")
            end
          end

          sclass = cl.superclass
          next if sclass.nil? || sclass == 'Object'
          sclass_full_name = find_full_name(sclass,cl)
          unless @local_names.include?(sclass_full_name) or @global_names.include?(sclass_full_name)
            path = sclass_full_name.split("::")
            url = File.join('classes', *path) + ".html"
            @global_graph << DOT::Node.new('name' => "#{sclass_full_name.gsub( /:/, '_' )}",
                                           'label' => sclass_full_name,
                                           'URL'   => %{"#{url}"})
            @global_names << sclass_full_name
          end
          @global_graph << DOT::Edge.new('from' => "#{sclass_full_name.gsub( /:/,'_' )}",
                                         'to' => "#{cl.full_name.gsub( /:/, '_')}")
        end
      end

      container.modules.each do |submod|
        draw_module(submod, graph)
      end

    end

    def convert_to_png(file_base, graph)
      str = graph.to_s
      return @diagram_cache[str] if @diagram_cache[str]
      op_type = @options.image_format
      dotfile = File.join(DOT_PATH, file_base)
      src = dotfile + ".dot"
      dot = dotfile + "." + op_type

      unless @options.quiet
        $stderr.print "."
        $stderr.flush
      end

      File.open(src, 'w+' ) do |f|
        f << str << "\n"
      end

      system "dot", "-T#{op_type}", src, "-o", dot

      # Now construct the imagemap wrapper around
      # that png

      ret = wrap_in_image_map(src, dot)
      @diagram_cache[str] = ret
      return ret
    end

    ##
    # Extract the client-side image map from dot, and use it to generate the
    # imagemap proper. Return the whole <map>..<img> combination, suitable for
    # inclusion on the page

    def wrap_in_image_map(src, dot)
      res = ""
      dot_map = `dot -Tismap #{src}`

      if(!dot_map.empty?)
        res << %{<map id="map" name="map">\n}
        dot_map.split($/).each do |area|
          unless area =~ /^rectangle \((\d+),(\d+)\) \((\d+),(\d+)\) ([\/\w.]+)\s*(.*)/
            $stderr.puts "Unexpected output from dot:\n#{area}"
            return nil
          end

          xs, ys = [$1.to_i, $3.to_i], [$2.to_i, $4.to_i]
          url, area_name = $5, $6

          res <<  %{  <area shape="rect" coords="#{xs.min},#{ys.min},#{xs.max},#{ys.max}" }
          res <<  %{     href="#{url}" alt="#{area_name}" />\n}
        end
        res << "</map>\n"
      end

      res << %{<img src="#{dot}" usemap="#map" alt="#{dot}" />}
      return res
    end

  end

end
