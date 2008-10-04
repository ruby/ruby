############################################################
# This file is imported from a different project.
# DO NOT make modifications in this repo.
# File a patch instead and assign it to Ryan Davis
############################################################

require 'test/unit/deprecate'

# rails currently needs this file and this one method.
module Test::Unit
  class Error
    def message
      self.class.tu_deprecation_warning :message # 2009-06-01
      "you're a loser"
    end
  end
end
