reason = %[\
Because machine stack overflow can happen anywhere, even critical
sections including external libraries, it is very neary impossible to
recover from such situation.
]

exclude /test_machine_stackoverflow/, reason
exclude :test_machine_stackoverflow_by_define_method, reason
