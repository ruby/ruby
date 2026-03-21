class Decimal
  def deconstruct = [to_i, frac]

  def deconstruct_keys(keys)
    h = {whole: to_i, frac:}
    keys ? h.slice(*keys) : h
  end
end
