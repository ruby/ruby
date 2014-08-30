require 'multi_json/options'
require 'multi_json/version'
require 'multi_json/adapter_error'
require 'multi_json/parse_error'

module MultiJson
  include Options
  extend self

  def default_options=(value)
    Kernel.warn "MultiJson.default_options setter is deprecated\n" +
      "Use MultiJson.load_options and MultiJson.dump_options instead"

    self.load_options = self.dump_options = value
  end

  def default_options
    Kernel.warn "MultiJson.default_options is deprecated\n" +
      "Use MultiJson.load_options or MultiJson.dump_options instead"

    self.load_options
  end

  %w[cached_options reset_cached_options!].each do |method_name|
    define_method method_name do |*|
      Kernel.warn "MultiJson.#{method_name} method is deprecated and no longer used."
    end
  end

  ALIASES = { 'jrjackson' => 'jr_jackson' }

  REQUIREMENT_MAP = [
    ['oj',           :oj],
    ['yajl',         :yajl],
    ['jrjackson',    :jr_jackson],
    ['json/ext',     :json_gem],
    ['gson',         :gson],
    ['json/pure',    :json_pure]
  ]

  # The default adapter based on what you currently
  # have loaded and installed. First checks to see
  # if any adapters are already loaded, then checks
  # to see which are installed if none are loaded.
  def default_adapter
    return :oj if defined?(::Oj)
    return :yajl if defined?(::Yajl)
    return :jr_jackson if defined?(::JrJackson)
    return :json_gem if defined?(::JSON::JSON_LOADED)
    return :gson if defined?(::Gson)

    REQUIREMENT_MAP.each do |library, adapter|
      begin
        require library
        return adapter
      rescue ::LoadError
        next
      end
    end

    Kernel.warn '[WARNING] MultiJson is using the default adapter (ok_json).' +
      'We recommend loading a different JSON library to improve performance.'

    :ok_json
  end
  alias default_engine default_adapter

  # Get the current adapter class.
  def adapter
    return @adapter if defined?(@adapter) && @adapter

    self.use nil # load default adapter

    @adapter
  end
  alias engine adapter

  # Set the JSON parser utilizing a symbol, string, or class.
  # Supported by default are:
  #
  # * <tt>:oj</tt>
  # * <tt>:json_gem</tt>
  # * <tt>:json_pure</tt>
  # * <tt>:ok_json</tt>
  # * <tt>:yajl</tt>
  # * <tt>:nsjsonserialization</tt> (MacRuby only)
  # * <tt>:gson</tt> (JRuby only)
  # * <tt>:jr_jackson</tt> (JRuby only)
  def use(new_adapter)
    @adapter = load_adapter(new_adapter)
  end
  alias adapter= use
  alias engine= use

  def load_adapter(new_adapter)
    case new_adapter
    when String, Symbol
      load_adapter_from_string_name new_adapter.to_s
    when NilClass, FalseClass
      load_adapter default_adapter
    when Class, Module
      new_adapter
    else
      raise ::LoadError, new_adapter
    end
  rescue ::LoadError => exception
    raise AdapterError.build(exception)
  end

  # Decode a JSON string into Ruby.
  #
  # <b>Options</b>
  #
  # <tt>:symbolize_keys</tt> :: If true, will use symbols instead of strings for the keys.
  # <tt>:adapter</tt> :: If set, the selected adapter will be used for this call.
  def load(string, options={})
    adapter = current_adapter(options)
    begin
      adapter.load(string, options)
    rescue adapter::ParseError => exception
      raise ParseError.build(exception, string)
    end
  end
  alias decode load

  def current_adapter(options={})
    if new_adapter = options[:adapter]
      load_adapter(new_adapter)
    else
      adapter
    end
  end

  # Encodes a Ruby object as JSON.
  def dump(object, options={})
    current_adapter(options).dump(object, options)
  end
  alias encode dump

  #  Executes passed block using specified adapter.
  def with_adapter(new_adapter)
    old_adapter, self.adapter = adapter, new_adapter
    yield
  ensure
    self.adapter = old_adapter
  end
  alias with_engine with_adapter

  private

  def load_adapter_from_string_name(name)
    name = ALIASES.fetch(name, name)
    require "multi_json/adapters/#{name.downcase}"
    klass_name = name.to_s.split('_').map(&:capitalize) * ''
    MultiJson::Adapters.const_get(klass_name)
  end

end
