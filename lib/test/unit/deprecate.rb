############################################################
# This file is imported from a different project.
# DO NOT make modifications in this repo.
# File a patch instead and assign it to Ryan Davis
############################################################

class Module # define deprecation api
  DEPS = Hash.new { |h,k| h[k] = {} }

  def tu_deprecation_warning old, new = nil, kaller = nil
    kaller ||= caller[1]
    unless DEPS[old][kaller] then
      msg = "#{self}##{old} deprecated. "
      msg += new ? "Use ##{new}" : "No replacement is provided"
      msg += ". From #{kaller}."
      warn msg
    end
    DEPS[old][kaller] = true
  end

  def tu_deprecate old, new
    class_eval <<-EOM
      def #{old} *args, &block
        cls, clr = self.class, caller.first
        self.class.tu_deprecation_warning #{old.inspect}, #{new.inspect}, clr
        #{new}(*args, &block)
      end
    EOM
  end
end
