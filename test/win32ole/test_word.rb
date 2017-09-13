# frozen_string_literal: false
#
# This is test for [ruby-Bugs#3237]
#
begin
  require 'win32ole'
rescue LoadError
end
require "test/unit"

if defined?(WIN32OLE)
  module Word; end
end

def word_installed?
  installed = false
  w = nil
  if defined?(WIN32OLE)
    begin
      w = WIN32OLE.new('Word.Application')
      WIN32OLE.const_load(w, Word)
      installed = true
    rescue
    ensure
      if w
        w.quit(Word::WdDoNotSaveChanges)
        w = nil
      end
    end
  end
  return installed
end

if defined?(WIN32OLE)
  class TestWIN32OLE_WITH_WORD < Test::Unit::TestCase
    unless word_installed?
      def test_dummy_for_skip_message
        skip "Microsoft Word is not installed"
      end
    else
      def setup
        begin
          @obj = WIN32OLE.new('Word.Application')
        rescue WIN32OLERuntimeError
          @obj = nil
        end
      end

      def test_ole_methods
        if @obj
          @obj.visible = true
          @obj.wordbasic.disableAutoMacros(true)
          assert(true)
        end
      end

      def test_s_connect
        if @obj
          obj2 = WIN32OLE.connect("Word.Application")
          assert_instance_of(WIN32OLE, obj2)
          obj2.visible = true
        end
      end

      def teardown
        if @obj
          @obj.quit(Word::WdDoNotSaveChanges)
          @obj = nil
        end
      end
    end
  end
end
