require 'rdoc/rdoc'
require 'rdoc/generator'
require 'rdoc/markup/to_texinfo'

module RDoc
  module Generator
    # This generates Texinfo files for viewing with GNU Info or Emacs
    # from RDoc extracted from Ruby source files.
    class TEXINFO
      # What should the .info file be named by default?
      DEFAULT_INFO_FILENAME = 'rdoc.info'

      include Generator::MarkUp

      # Accept some options
      def initialize(options)
        @options = options
        @options.inline_source = true
        @options.op_name ||= 'rdoc.texinfo'
        @options.formatter = ::RDoc::Markup::ToTexInfo.new
      end

      # Generate the +texinfo+ files
      def generate(toplevels)
        @toplevels = toplevels
        @files, @classes = ::RDoc::Generator::Context.build_indices(@toplevels,
                                                                    @options)

        (@files + @classes).each { |x| x.value_hash }

        open(@options.op_name, 'w') do |f|
          f.puts TexinfoTemplate.new('files' => @files,
                                     'classes' => @classes,
                                     'filename' => @options.op_name.gsub(/texinfo/, 'info'),
                                     'title' => @options.title).render
        end
        # TODO: create info files and install?
      end

      class << self
        # Factory? We don't need no stinkin' factory!
        alias_method :for, :new
      end
    end

    # Basically just a wrapper around ERB.
    # Should probably use RDoc::TemplatePage instead
    class TexinfoTemplate
      BASE_DIR = ::File.expand_path(::File.dirname(__FILE__)) # have to calculate this when the file's loaded.

      def initialize(values, file = 'texinfo.erb')
        @v, @file = [values, file]
      end
     
      def template
        ::File.read(::File.join(BASE_DIR, 'texinfo', @file))
      end

      # Go!
      def render
        ERB.new(template).result binding
      end

      def href(location, text)
        text # TODO: how does texinfo do hyperlinks?
      end

      def target(name, text)
        text # TODO: how do hyperlink targets work?
      end

      # TODO: this is probably implemented elsewhere?
      def method_prefix(section)
        { 'Class' => '.',
          'Module' => '::',
          'Instance' => '#',
        }[section['category']]
      end
    end
  end
end
