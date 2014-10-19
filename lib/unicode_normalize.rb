# coding: utf-8

# Copyright Ayumu Nojima (野島 歩) and Martin J. Dürst (duerst@it.aoyama.ac.jp)

require 'unicode_normalize/normalize.rb'

class String
  def unicode_normalize(form = :nfc)
    UnicodeNormalize.normalize(self, form)
  end

  def unicode_normalize!(form = :nfc)
    replace(self.normalize(form))
  end

  def unicode_normalized?(form = :nfc)
    UnicodeNormalize.normalized?(self, form)
  end
end

