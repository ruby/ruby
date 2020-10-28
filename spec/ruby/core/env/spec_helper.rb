require_relative '../../spec_helper'

locale_env_matcher = Class.new do
  def initialize(name = 'locale')
    encoding = Encoding.find(name)
    @encodings = (encoding = Encoding::US_ASCII) ?
                   [encoding, Encoding::ASCII_8BIT] : [encoding]
  end

  def matches?(actual)
    @actual = actual = actual.encoding
    @encodings.include?(actual)
  end

  def failure_message
    ["Expected #{@actual} to be #{@encodings.join(' or ')}"]
  end

  def negative_failure_message
    ["Expected #{@actual} not to be #{@encodings.join(' or ')}"]
  end
end

String.__send__(:define_method, :be_locale_env) do |expected = 'locale'|
  locale_env_matcher.new(expected)
end
