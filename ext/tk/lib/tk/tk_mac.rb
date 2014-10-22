#
# tk/tk_mac.rb : Access Mac-Specific functionality on OS X from Tk
#                (supported by Tk8.6 or later)
#
#     ATTENTION !!
#         This is NOT TESTED. Because I have no test-environment.
#
require 'tk'

module Tk
  module Mac
  end
end

module Tk::Mac
  extend TkCore

  # event handler callbacks
  def self.def_ShowPreferences(cmd=Proc.new)
    ip_eval("proc ::tk::mac::ShowPreferences {} { #{install_cmd(cmd)} }")
    nil
  end

  def self.def_OpenApplication(cmd=Proc.new)
    ip_eval("proc ::tk::mac::OpenApplication {} { #{install_cmd(cmd)} }")
    nil
  end

  def self.def_ReopenApplication(cmd=Proc.new)
    ip_eval("proc ::tk::mac::ReopenApplication {} { #{install_cmd(cmd)} }")
    nil
  end

  def self.def_OpenDocument(cmd=Proc.new)
    ip_eval("proc ::tk::mac::OpenDocument {args} { eval #{install_cmd(cmd)} $args }")
    nil
  end

  def self.def_PrintDocument(cmd=Proc.new)
    ip_eval("proc ::tk::mac::PrintDocument {args} { eval #{install_cmd(cmd)} $args }")
    nil
  end

  def self.def_Quit(cmd=Proc.new)
    ip_eval("proc ::tk::mac::Quit {} { #{install_cmd(cmd)} }")
    nil
  end

  def self.def_OnHide(cmd=Proc.new)
    ip_eval("proc ::tk::mac::OnHide {} { #{install_cmd(cmd)} }")
    nil
  end

  def self.def_OnShow(cmd=Proc.new)
    ip_eval("proc ::tk::mac::OnShow {} { #{install_cmd(cmd)} }")
    nil
  end

  def self.def_ShowHelp(cmd=Proc.new)
    ip_eval("proc ::tk::mac::ShowHelp {} { #{install_cmd(cmd)} }")
    nil
  end


  # additional dialogs
  def self.standardAboutPanel
    tk_call('::tk::mac::standardAboutPanel')
    nil
  end


  # system configuration
  def self.useCompatibilityMetrics(mode)
    tk_call('::tk::mac::useCompatibilityMetrics', mode)
    nil
  end

  def self.CGAntialiasLimit(limit)
    tk_call('::tk::mac::CGAntialiasLimit', limit)
    nil
  end

  def self.antialiasedtext(num)
    tk_call('::tk::mac::antialiasedtext', num)
    nil
  end

  def self.useThemedToplevel(mode)
    tk_call('::tk::mac::useThemedToplevel', mode)
    nil
  end

end

class Tk::Mac::IconBitmap < TkImage
  TkCommandNames = ['::tk::mac::iconBitmap'].freeze

  def self.new(width, height, keys)
    if keys.kind_of?(Hash)
      name = nil
      if keys.key?(:imagename)
        name = keys[:imagename]
      elsif keys.key?('imagename')
        name = keys['imagename']
      end
      if name
        if name.kind_of?(TkImage)
          obj = name
        else
          name = _get_eval_string(name)
          obj = nil
          Tk_IMGTBL.mutex.synchronize{
            obj = Tk_IMGTBL[name]
          }
        end
        if obj
          if !(keys[:without_creating] || keys['without_creating'])
            keys = _symbolkey2str(keys)
            keys.delete('imagename')
            keys.delete('without_creating')
            obj.instance_eval{
              tk_call_without_enc('::tk::mac::iconBitmap',
                                  @path, width, height, *hash_kv(keys, true))
            }
          end
          return obj
        end
      end
    end
    (obj = self.allocate).instance_eval{
      Tk_IMGTBL.mutex.synchronize{
        initialize(width, height, keys)
        Tk_IMGTBL[@path] = self
      }
    }
    obj
  end

  def initialize(width, height, keys)
    @path = nil
    without_creating = false
    if keys.kind_of?(Hash)
      keys = _symbolkey2str(keys)
      @path = keys.delete('imagename')
      without_creating = keys.delete('without_creating')
    end
    unless @path
      Tk_Image_ID.mutex.synchronize{
        @path = Tk_Image_ID.join(TkCore::INTERP._ip_id_)
        Tk_Image_ID[1].succ!
      }
    end
    unless without_creating
      tk_call_without_enc('::tk::mac::iconBitmap',
                          @path, width, height, *hash_kv(keys, true))
    end
  end
end
