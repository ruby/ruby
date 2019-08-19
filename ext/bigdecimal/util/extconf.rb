# frozen_string_literal: false
require 'mkmf'

checking_for(checking_message("Windows")) do
  case RUBY_PLATFORM
  when /cygwin|mingw/
    if defined?($extlist)
      build_dir = "$(TARGET_SO_DIR)../"
    else
      base_dir = File.expand_path('../../../..', __FILE__)
      build_dir = File.join(base_dir, "tmp", RUBY_PLATFORM, "bigdecimal", RUBY_VERSION, "")
    end
    $libs << " #{build_dir}bigdecimal.so"
    true
  when /mswin/
    $DLDFLAGS << " -libpath:.."
    $libs << " bigdecimal-$(arch).lib"
    true
  else
    false
  end
end

create_makefile('bigdecimal/util')
