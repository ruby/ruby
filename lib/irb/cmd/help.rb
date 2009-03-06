#
#   help.rb - helper using ri
#   	$Release Version: 0.9.5$
#   	$Revision$
#
# --
#
#
#

require 'rdoc/ri/driver'
require 'rdoc/ri/util'

module IRB
  module ExtendCommand
    module Help
      begin
        @ri = RDoc::RI::Driver.new
      rescue SystemExit
      else
        def self.execute(context, *names)
          names.each do |name|
            begin
              @ri.get_info_for(name.to_s)
            rescue RDoc::RI::Error
              puts $!.message
            end
          end
          nil
        end
      end
    end
  end
end
