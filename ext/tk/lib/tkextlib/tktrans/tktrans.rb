#
#  TkTrans support (win32 only)
#                               by Hidetoshi NAGAI (nagai@ai.kyutech.ac.jp)
#
require 'tk'

# call setup script for general 'tkextlib' libraries
require 'tkextlib/setup.rb'

# call setup script
require File.join(File.dirname(File.expand_path(__FILE__)), 'setup.rb')

TkPackage.require('tktrans') rescue Tk.load_tcllibrary('tktrans')

class TkWindow
  begin
    TkTrans_VERSION = TkPackage.require('tktrans')
  rescue
    TkTrans_VERSION = nil
  end

  def tktrans_set_image(img)
    tk_send('tktrans::setwidget', @path, img)
    self
  end
  def tktrans_get_image()
    tk_send('tktrans::setwidget', @path)
  end
end

class TkRoot
  undef tktrans_set_image, tktrans_get_image

  def tktrans_set_image(img)
    tk_send('tktrans::settoplevel', @path, img)
    self
  end
  def tktrans_get_image()
    tk_send('tktrans::settoplevel', @path)
  end
end

class TkToplevel
  undef tktrans_set_image, tktrans_get_image

  def tktrans_set_image(img)
    tk_send('tktrans::settoplevel', @path, img)
    self
  end
  def tktrans_get_image()
    tk_send('tktrans::settoplevel', @path)
  end
end
