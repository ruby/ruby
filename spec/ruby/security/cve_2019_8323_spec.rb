require_relative '../spec_helper'

require 'optparse'

require 'rubygems'
require 'rubygems/gemcutter_utilities'

describe "CVE-2019-8323 is resisted by" do
  describe "sanitising the body" do
    it "for success codes" do
      cutter = Class.new {
        include Gem::GemcutterUtilities
      }.new
      klass = if defined?(Gem::Net::HTTPSuccess)
                Gem::Net::HTTPSuccess
              else
                Net::HTTPSuccess
              end
      response = klass.new(nil, nil, nil)
      def response.body
        "\e]2;nyan\a"
      end
      cutter.should_receive(:say).with(".]2;nyan.")
      cutter.with_response response
    end

    it "for error codes" do
      cutter = Class.new {
        include Gem::GemcutterUtilities
      }.new
      def cutter.terminate_interaction(n)
      end
      klass = if defined?(Gem::Net::HTTPNotFound)
                Gem::Net::HTTPNotFound
              else
                Net::HTTPNotFound
              end
      response = klass.new(nil, nil, nil)
      def response.body
        "\e]2;nyan\a"
      end
      cutter.should_receive(:say).with(".]2;nyan.")
      cutter.with_response response
    end
  end
end
