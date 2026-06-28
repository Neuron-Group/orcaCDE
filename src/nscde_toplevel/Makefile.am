#
# NsCDE foreign toplevel daemon for labwc backend.
#
# This file is a part of NsCDE - Not so Common Desktop Environment
# Author: Hegel3DReloaded
# Licence: GPLv3
#

machdepdir = $(NSCDE_TOOLSDIR)/$(OS_PLUS_MACHINE_ARCH)
machdep_PROGRAMS = nscde_toplevel

nscde_toplevel_SOURCES = nscde_toplevel.c \
	../nscde_wayland_common/runtime-client.c \
	../nscde_wayland_common/runtime-client.h \
	wlr-foreign-toplevel-management-unstable-v1-client-protocol.h \
	wlr-foreign-toplevel-management-unstable-v1-protocol.c

nscde_toplevel_CFLAGS = $(WAYLAND_CLIENT_CFLAGS)

nscde_toplevel_LDADD = $(WAYLAND_CLIENT_LIBS)

# Generate client protocol header and code from wlroots protocol
BUILT_SOURCES = wlr-foreign-toplevel-management-unstable-v1-client-protocol.h \
	wlr-foreign-toplevel-management-unstable-v1-protocol.c

wlr-foreign-toplevel-management-unstable-v1-client-protocol.h:
	$(WAYLAND_SCANNER) client-header \
		$(WLR_PROTOCOLS_DIR)/wlr-foreign-toplevel-management-unstable-v1.xml \
		$@

wlr-foreign-toplevel-management-unstable-v1-protocol.c:
	$(WAYLAND_SCANNER) private-code \
		$(WLR_PROTOCOLS_DIR)/wlr-foreign-toplevel-management-unstable-v1.xml \
		$@

clean-local:
	-rm -f wlr-foreign-toplevel-management-unstable-v1-client-protocol.h \
		wlr-foreign-toplevel-management-unstable-v1-protocol.c

uninstall-hook:
	rmdir $(machdepdir) || true
