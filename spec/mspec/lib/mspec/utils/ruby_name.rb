unless Object.const_defined?(:RUBY_NAME) and RUBY_NAME
  if Object.const_defined?(:RUBY_ENGINE) and RUBY_ENGINE
    RUBY_NAME = RUBY_ENGINE
  else
    require 'rbconfig'
    RUBY_NAME = RbConfig::CONFIG["RUBY_INSTALL_NAME"] || RbConfig::CONFIG["ruby_install_name"]
  end
end
