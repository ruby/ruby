require "rss/0.9"

module RSS

  class Rss

    class Channel

      %w(generator ttl).each do |name|
        install_text_element(name)
        install_model(name, '?')
      end

      remove_method :ttl=
      def ttl=(value)
        @ttl = value.to_i
      end
      
      [
        %w(category categories),
      ].each do |name, plural_name|
        install_have_children_element(name, plural_name)
        install_model(name, '*')
      end
        
      [
        ["image", "?"],
        ["language", "?"],
      ].each do |name, occurs|
        install_model(name, occurs)
      end

      def other_element(need_convert, indent)
        rv = <<-EOT
#{category_elements(need_convert, indent)}
#{generator_element(need_convert, indent)}
#{ttl_element(need_convert, indent)}
EOT
        rv << super
      end
      
      private
      alias children09 children
      def children
        children09 + @category.compact
      end

      alias _tags09 _tags
      def _tags
        rv = %w(generator ttl).delete_if do |name|
          send(name).nil?
        end.collect do |elem|
          [nil, elem]
        end + _tags09

        @category.each do
          rv << [nil, "category"]
        end
        
        rv
      end

      Category = Item::Category

      class Item
      
        [
          ["comments", "?"],
          ["author", "?"],
        ].each do |name, occurs|
          install_text_element(name)
          install_model(name, occurs)
        end

        [
          ["pubDate", '?'],
        ].each do |name, occurs|
          install_date_element(name, 'rfc822')
          install_model(name, occurs)
        end
        alias date pubDate
        alias date= pubDate=

        [
          ["guid", '?'],
        ].each do |name, occurs|
          install_have_child_element(name)
          install_model(name, occurs)
        end
      
        def other_element(need_convert, indent)
          rv = [
            super,
            *%w(author comments pubDate guid).collect do |name|
              __send__("#{name}_element", false, indent)
            end
          ].reject do |value|
            /\A\s*\z/.match(value)
          end
          rv.join("\n")
        end

        private
        alias children09 children
        def children
          children09 + [@guid].compact
        end

        alias _tags09 _tags
        def _tags
          %w(comments author pubDate guid).delete_if do |name|
            send(name).nil?
          end.collect do |elem|
            [nil, elem]
          end + _tags09
        end

        alias _setup_maker_element setup_maker_element
        def setup_maker_element(item)
          _setup_maker_element(item)
          @guid.setup_maker(item) if @guid
        end
        
        class Guid < Element
          
          include RSS09

          [
            ["isPermaLink", nil, false]
          ].each do |name, uri, required|
            install_get_attribute(name, uri, required)
          end

          content_setup

          def initialize(isPermaLink=nil, content=nil)
            super()
            @isPermaLink = isPermaLink
            @content = content
          end

          private
          def _attrs
            [
              ["isPermaLink", false]
            ]
          end

          def maker_target(item)
            item.guid
          end

          def setup_maker_attributes(guid)
            guid.isPermaLink = isPermaLink
            guid.content = content
          end
        end

      end

    end

  end

  RSS09::ELEMENTS.each do |name|
    BaseListener.install_get_text_element(nil, name, "#{name}=")
  end

end
