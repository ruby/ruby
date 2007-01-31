#
#   help.rb - helper using ri
#   	$Release Version: 0.9.5$
#   	$Revision: 1.2.4.1 $
#   	$Date: 2005/04/19 19:24:58 $
#
# --
#
#   
#

require 'rdoc/ri/ri_driver'

module IRB
  module ExtendCommand
    module Help
      begin
        @ri = RiDriver.new
      rescue SystemExit
      else
        def self.execute(context, *names)
          names.each do |name|
            begin
              @ri.get_info_for(name.to_s)
            rescue RiError
              puts $!.message
            end
          end
          nil
        end
      end
    end
  end
end
