require 'rdoc/ri/ri_paths'
require 'rdoc/ri/ri_cache'
require 'rdoc/ri/ri_util'
require 'rdoc/ri/ri_reader'
require 'rdoc/ri/ri_formatter'
require 'rdoc/ri/ri_options'


######################################################################

class  RiDriver

  def initialize
    @options = RI::Options.instance
    @options.parse
    paths = @options.paths || RI::Paths::PATH
    if paths.empty?
      $stderr.puts "No ri documentation found in:"
      [ RI::Paths::SYSDIR, RI::Paths::SITEDIR, RI::Paths::HOMEDIR].each do |d|
        $stderr.puts "     #{d}"
      end
      $stderr.puts "\nWas rdoc run to create documentation?"
      exit 1                   
    end
    @ri_reader = RI::RiReader.new(RI::RiCache.new(paths))
    @display   = @options.displayer
  end    
  
  
  
  ######################################################################
  
  # If the list of matching methods contains exactly one entry, or
  # if it contains an entry that exactly matches the requested method,
  # then display that entry, otherwise display the list of
  # matching method names
  
  def report_method_stuff(requested_method_name, methods)
    if methods.size == 1
      method = @ri_reader.get_method(methods[0])
      @display.display_method_info(method)
    else
      entries = methods.find_all {|m| m.name == requested_method_name}
      if entries.size == 1
        method = @ri_reader.get_method(entries[0])
        @display.display_method_info(method)
      else
        @display.display_method_list(methods)
      end
    end
  end
  
  ######################################################################
  
  def report_class_stuff(namespaces)
    if namespaces.size == 1
      klass = @ri_reader.get_class(namespaces[0])
      @display.display_class_info(klass, @ri_reader)
    else 
#      entries = namespaces.find_all {|m| m.full_name == requested_class_name}
#      if entries.size == 1
#        klass = @ri_reader.get_class(entries[0])
#        @display.display_class_info(klass, @ri_reader)
#      else
        @display.display_class_list(namespaces)
#      end
    end
  end
  
  ######################################################################
  
  
  def get_info_for(arg)
    desc = NameDescriptor.new(arg)
    
    namespaces = @ri_reader.top_level_namespace
    
    for class_name in desc.class_names
      namespaces = @ri_reader.lookup_namespace_in(class_name, namespaces)
      if namespaces.empty?
        raise RiError.new("Nothing known about #{arg}")
      end
    end

    # at this point, if we have multiple possible namespaces, but one
    # is an exact match for our requested class, prune down to just it

    full_class_name = desc.full_class_name
    entries = namespaces.find_all {|m| m.full_name == full_class_name}
    namespaces = entries if entries.size == 1

    if desc.method_name.nil?
      report_class_stuff(namespaces)
    else
      methods = @ri_reader.find_methods(desc.method_name, 
                                        desc.is_class_method,
                                        namespaces)
      
      if methods.empty?
        raise RiError.new("Nothing known about #{arg}")
      else
        report_method_stuff(desc.method_name, methods)
      end
    end
  end

  ######################################################################

  def process_args
    if @options.list_classes
      classes = @ri_reader.class_names
      @display.list_known_classes(classes)
    else
      if ARGV.size.zero?
        @display.display_usage
      else
        begin
          ARGV.each do |arg|
            get_info_for(arg)
          end
        rescue RiError => e
          $stderr.puts(e.message)
          exit(1)
        end
      end
    end
  end

end  # class RiDriver
