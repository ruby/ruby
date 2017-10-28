module TracePointSpec
  class ClassWithMethodAlias
    def m
    end
    alias_method :m_alias, :m
  end
end

