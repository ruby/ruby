# frozen_string_literal: false
require 'mkmf'

def windows_platform?
  /cygwin|mingw|mswin/ === RUBY_PLATFORM
end

if windows_platform?
  library_base_name = "ruby-bigdecimal"
  case RUBY_PLATFORM
  when /cygwin|mingw/
    import_library_name = "libruby-bigdecimal.a"
  when /mswin/
    import_library_name = "bigdecimal-$(arch).lib"
  end
end

checking_for(checking_message("Windows")) do
  if windows_platform?
    if defined?($extlist)
      build_dir = "$(TARGET_SO_DIR)../"
    else
      base_dir = File.expand_path('../../../..', __FILE__)
      build_dir = File.join(base_dir, "tmp", RUBY_PLATFORM, "bigdecimal", RUBY_VERSION)
    end
    case RUBY_PLATFORM
    when /cygwin|mingw/
      $LDFLAGS << " -L#{build_dir} -L.. -L .."
      $libs << " -l#{library_base_name}"
    when /mswin/
      $DLDFLAGS << " /libpath:#{build_dir} /libpath:.."
      $libs << " #{import_library_name}"
    end
    true
  else
    false
  end
end

create_makefile('bigdecimal/util')
