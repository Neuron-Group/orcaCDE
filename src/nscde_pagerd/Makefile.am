#
# NsCDE workspace pager daemon for labwc backend.
#
# This file is a part of NsCDE - Not so Common Desktop Environment
# Author: Hegel3DReloaded
# Licence: GPLv3
#

machdepdir = $(NSCDE_TOOLSDIR)/$(OS_PLUS_MACHINE_ARCH)
machdep_PROGRAMS = nscde_pagerd

nscde_pagerd_SOURCES = nscde_pagerd.c \
	../nscde_wayland_common/runtime-client.c \
	../nscde_wayland_common/runtime-client.h \
	ext-workspace-v1-client-protocol.h \
	ext-workspace-v1-protocol.c

nscde_pagerd_CFLAGS = $(WAYLAND_CLIENT_CFLAGS)

nscde_pagerd_LDADD = $(WAYLAND_CLIENT_LIBS)

# Generate client protocol header and code from wayland-protocols
BUILT_SOURCES = ext-workspace-v1-client-protocol.h ext-workspace-v1-protocol.c

ext-workspace-v1-client-protocol.h:
	$(WAYLAND_SCANNER) client-header \
		$(WAYLAND_PROTOCOLS_DATADIR)/staging/ext-workspace/ext-workspace-v1.xml \
		$@

ext-workspace-v1-protocol.c:
	$(WAYLAND_SCANNER) private-code \
		$(WAYLAND_PROTOCOLS_DATADIR)/staging/ext-workspace/ext-workspace-v1.xml \
		$@

clean-local:
	-rm -f ext-workspace-v1-client-protocol.h ext-workspace-v1-protocol.c

uninstall-hook:
	rmdir $(machdepdir) || true
