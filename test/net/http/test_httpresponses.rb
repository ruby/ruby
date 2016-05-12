# frozen_string_literal: false
require 'net/http'
require 'test/unit'

class HTTPResponsesTest < Test::Unit::TestCase
  def test_status_code_classes
    Net::HTTPResponse::CODE_TO_OBJ.each_pair { |code, klass|
      case code
      when /\A1\d\d\z/
        group = Net::HTTPInformation
      when /\A2\d\d\z/
        group = Net::HTTPSuccess
      when /\A3\d\d\z/
        group = Net::HTTPRedirection
      when /\A4\d\d\z/
        group = Net::HTTPClientError
      when /\A5\d\d\z/
        group = Net::HTTPServerError
      else
        flunk "Unknown HTTP status code: #{code} => #{klass.name}"
      end
      assert(klass < group, "#{klass.name} (#{code}) must inherit from #{group.name}")
    }
  end
end
