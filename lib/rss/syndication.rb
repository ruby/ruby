require "rss/1.0"

module RSS

  SY_PREFIX = 'sy'
  SY_URI = "http://purl.org/rss/1.0/modules/syndication/"

  RDF.install_ns(SY_PREFIX, SY_URI)

  module SyndicationModel
    
    extend BaseModel
    
    ELEMENTS = []
    
    def self.append_features(klass)
      super
      
      klass.module_eval(<<-EOC, *get_file_and_line_from_caller(1))
        %w(updatePeriod updateFrequency).each do |name|
          install_text_element("\#{SY_PREFIX}_\#{name}")
        end

        %w(updateBase).each do |name|
          install_date_element("\#{SY_PREFIX}_\#{name}", 'w3cdtf', name)
        end

        alias_method(:_sy_updatePeriod=, :sy_updatePeriod=)
        def sy_updatePeriod=(new_value)
          new_value = new_value.strip
          validate_sy_updatePeriod(new_value) if @do_validate
          self._sy_updatePeriod = new_value
        end

        alias_method(:_sy_updateFrequency=, :sy_updateFrequency=)
        def sy_updateFrequency=(new_value)
          validate_sy_updateFrequency(new_value) if @do_validate
          self._sy_updateFrequency = new_value.to_i
        end
      EOC
    end

    def sy_validate(tags)
      counter = {}
      ELEMENTS.each do |name|
        counter[name] = 0
      end

      tags.each do |tag|
        key = "#{SY_PREFIX}_#{tag}"
        raise UnknownTagError.new(tag, SY_URI)  unless counter.has_key?(key)
        counter[key] += 1
        raise TooMuchTagError.new(tag, tag_name) if counter[key] > 1
      end
    end

    private
    SY_UPDATEPERIOD_AVAILABLE_VALUES = %w(hourly daily weekly monthly yearly)
    def validate_sy_updatePeriod(value)
      unless SY_UPDATEPERIOD_AVAILABLE_VALUES.include?(value)
        raise NotAvailableValueError.new("updatePeriod", value)
      end
    end

    SY_UPDATEFREQUENCY_AVAILABLE_RE = /\A\s*\+?\d+\s*\z/
    def validate_sy_updateFrequency(value)
      value = value.to_s.strip
      if SY_UPDATEFREQUENCY_AVAILABLE_RE !~ value
        raise NotAvailableValueError.new("updateFrequency", value)
      end
    end

  end

  class RDF
    class Channel; include SyndicationModel; end
  end

  prefix_size = SY_PREFIX.size + 1
  SyndicationModel::ELEMENTS.uniq!
  SyndicationModel::ELEMENTS.each do |full_name|
    name = full_name[prefix_size..-1]
    BaseListener.install_get_text_element(SY_URI, name, "#{full_name}=")
  end

end
