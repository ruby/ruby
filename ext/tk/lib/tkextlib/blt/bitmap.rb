#
#  tkextlib/blt/bitmap.rb
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#

require 'tk'
require 'tkextlib/blt.rb'

module Tk::BLT
  class Bitmap < TkObject
    extend TkCore

    TkCommandNames = ['::blt::bitmap'.freeze].freeze

    BITMAP_ID_TBL = TkCore::INTERP.create_table
    BITMAP_ID = ['blt_bitmap_id'.freeze, '00000'.taint].freeze

    def self.data(name)
      dat = tk_simple_list(tk_call('::blt::bitmap', 'data', name))
      [ tk_split_list(dat[0]), tk_simple_list(dat[1]) ]
    end

    def self.exist?(name)
      bool(tk_call('::blt::bitmap', 'exists', name))
    end

    def self.height(name)
      number(tk_call('::blt::bitmap', 'height', name))
    end

    def self.width(name)
      number(tk_call('::blt::bitmap', 'width', name))
    end

    def self.source(name)
      tk_simple_list(tk_call('::blt::bitmap', 'source', name))
    end

    #################################

    class << self
      alias _new new

      def new(data, keys={})
        _new(:data, data, keys)
      end
      alias define new

      def compose(text, keys={})
        _new(:text, text, keys)
      end
    end

    def initialize(type, data, keys = {})
      @id = BITMAP_ID.join(TkCore::INTERP._ip_id_)
      BITMAP_ID[1].succ!
      BITMAP_ID_TBL[@id] = self

      @path = @id

      if type == :text
        tk_call('::blt::bitmap', 'compose', @id, *hash_kv(keys))
      else # :data
        tk_call('::blt::bitmap', 'define', @id, *hash_kv(keys))
      end
    end

    def exist?
      bool(tk_call('::blt::bitmap', 'exists', @id))
    end

    def height
      number(tk_call('::blt::bitmap', 'height', @id))
    end

    def width
      number(tk_call('::blt::bitmap', 'width', @id))
    end

    def source
      tk_simple_list(tk_call('::blt::bitmap', 'source', @id))
    end
  end
end
