require 'mspec/guards/guard'

class SuperUserGuard < SpecGuard
  def match?
    Process.euid == 0
  end
end

def as_superuser(&block)
  SuperUserGuard.new.run_if(:as_superuser, &block)
end

def as_user(&block)
  SuperUserGuard.new.run_unless(:as_user, &block)
end
