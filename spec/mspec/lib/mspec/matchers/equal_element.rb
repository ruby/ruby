class EqualElementMatcher
  def initialize(element, attributes = nil, content = nil, options = {})
    @element = element
    @attributes = attributes
    @content = content
    @options = options
  end

  def matches?(actual)
    @actual = actual

    matched = true

    if @options[:not_closed]
      matched &&= actual =~ /^#{Regexp.quote("<" + @element)}.*#{Regexp.quote(">" + (@content || ''))}$/
    else
      matched &&= actual =~ /^#{Regexp.quote("<" + @element)}/
      matched &&= actual =~ /#{Regexp.quote("</" + @element + ">")}$/
      matched &&= actual =~ /#{Regexp.quote(">" + @content + "</")}/ if @content
    end

    if @attributes
      if @attributes.empty?
        matched &&= actual.scan(/\w+\=\"(.*)\"/).size == 0
      else
        @attributes.each do |key, value|
          if value == true
            matched &&= (actual.scan(/#{Regexp.quote(key)}(\s|>)/).size == 1)
          else
            matched &&= (actual.scan(%Q{ #{key}="#{value}"}).size == 1)
          end
        end
      end
    end

    !!matched
  end

  def failure_message
    ["Expected #{@actual.pretty_inspect}",
     "to be a '#{@element}' element with #{attributes_for_failure_message} and #{content_for_failure_message}"]
  end

  def negative_failure_message
    ["Expected #{@actual.pretty_inspect}",
      "not to be a '#{@element}' element with #{attributes_for_failure_message} and #{content_for_failure_message}"]
  end

  def attributes_for_failure_message
    if @attributes
      if @attributes.empty?
        "no attributes"
      else
        @attributes.inject([]) { |memo, n| memo << %Q{#{n[0]}="#{n[1]}"} }.join(" ")
      end
    else
      "any attributes"
    end
  end

  def content_for_failure_message
    if @content
      if @content.empty?
        "no content"
      else
        "#{@content.inspect} as content"
      end
    else
      "any content"
    end
  end
end

module MSpecMatchers
  private def equal_element(*args)
    EqualElementMatcher.new(*args)
  end
end
