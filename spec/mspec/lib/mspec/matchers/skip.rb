module MSpecMatchers
  private def skip(reason = 'no reason')
    raise SkippedSpecError, reason
  end
end
