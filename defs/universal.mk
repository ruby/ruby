arch_flags := $(filter -arch=%,$(subst -arch ,-arch=,$(ARCH_FLAG)))
ifeq ($(filter 0 1,$(words $(arch_flags))),)
override MJIT_HEADER_SUFFIX = -%
override MJIT_HEADER_ARCH = -$(word 2,$(ARCH_FLAG))
endif
