class Reline::KeyActor::Base
  MAPPING = Array.new(256)

  def get_method(key)
    self.class::MAPPING[key]
  end
end
