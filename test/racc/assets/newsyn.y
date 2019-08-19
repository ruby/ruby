
class A

  preclow
    left preclow prechigh right left nonassoc token
    right preclow prechigh right left nonassoc token
    nonassoc preclow prechigh right left nonassoc token
  prechigh

  convert
    left 'a'
    right 'b'
    preclow 'c'
    nonassoc 'd'
    preclow 'e'
    prechigh 'f'
  end

rule

  left: right nonassoc preclow prechigh

  right: A B C

end
