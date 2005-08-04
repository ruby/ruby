#
#  tprogressbar widget
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'
require 'tkextlib/tile.rb'

module Tk
  module Tile
    class TProgressbar < TkWindow
    end
    Progressbar = TProgressbar
  end
end

class Tk::Tile::TProgressbar
  include Tk::Tile::TileWidget

  if Tk::Tile::USE_TTK_NAMESPACE
    TkCommandNames = ['::ttk::progressbar'.freeze].freeze
  else
    TkCommandNames = ['::tprogressbar'.freeze].freeze
  end
  WidgetClassName = 'TProgressbar'.freeze
  WidgetClassNames[WidgetClassName] = self

  def self.style(*args)
    [self::WidgetClassName, *(args.map!{|a| _get_eval_string(a)})].join('.')
  end

  def step
    tk_send_without_enc('step').to_f
  end
  def step=(amount)
    tk_send_without_enc('step', amount)
  end

  def start(interval=None)
    tk_call_without_enc('::tile::progressbar::start', @path, interval)
  end

  def stop
    tk_call_without_enc('::tile::progressbar::stop', @path)
  end
end
