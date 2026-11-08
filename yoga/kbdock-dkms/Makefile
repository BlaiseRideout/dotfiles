# Out-of-tree build of lenovo-yb9-kbdock (see dkms.conf). The CachyOS kernel is
# built with clang + ThinLTO, and kbuild refuses a gcc build of a module for it,
# so pass LLVM=1 whenever the kernel's .config says it was built with clang.
obj-m := lenovo-yb9-kbdock.o

KVER ?= $(shell uname -r)
KDIR ?= /usr/lib/modules/$(KVER)/build

ifneq ($(shell grep -s '^CONFIG_CC_IS_CLANG=y' $(KDIR)/.config),)
KFLAGS_LLVM := LLVM=1
endif

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) $(KFLAGS_LLVM) modules

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) $(KFLAGS_LLVM) clean
