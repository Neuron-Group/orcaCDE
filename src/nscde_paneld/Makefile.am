#
# NsCDE layer-shell front panel daemon for labwc backend.
#
# This file is a part of NsCDE - Not so Common Desktop Environment
# Author: Hegel3DReloaded
# Licence: GPLv3
#

machdepdir = $(NSCDE_TOOLSDIR)/$(OS_PLUS_MACHINE_ARCH)
machdep_PROGRAMS = nscde_paneld

nscde_paneld_SOURCES = nscde_paneld.c \
	../nscde_wayland_common/panel-layout-contract.c \
	../nscde_wayland_common/panel-layout-contract.h \
	nscde-pixel-icon.c \
	nscde-pixel-icon.h \
	pool-buffer.c \
	pool-buffer.h \
	wlr-layer-shell-unstable-v1-client-protocol.h \
	wlr-layer-shell-unstable-v1-protocol.c \
	xdg-shell-client-protocol.h \
	xdg-shell-protocol.c

nscde_paneld_CFLAGS = $(WAYLAND_CLIENT_CFLAGS) \
	$(CAIRO_CFLAGS) $(PANGO_CFLAGS)

nscde_paneld_LDADD = $(WAYLAND_CLIENT_LIBS) \
	$(CAIRO_LIBS) $(PANGO_LIBS) -lm

BUILT_SOURCES = wlr-layer-shell-unstable-v1-client-protocol.h \
	wlr-layer-shell-unstable-v1-protocol.c \
	xdg-shell-client-protocol.h \
	xdg-shell-protocol.c

wlr-layer-shell-unstable-v1-client-protocol.h:
	$(WAYLAND_SCANNER) client-header \
		$(WLR_PROTOCOLS_DIR)/wlr-layer-shell-unstable-v1.xml \
		$@

wlr-layer-shell-unstable-v1-protocol.c:
	$(WAYLAND_SCANNER) private-code \
		$(WLR_PROTOCOLS_DIR)/wlr-layer-shell-unstable-v1.xml \
		$@

xdg-shell-client-protocol.h:
	$(WAYLAND_SCANNER) client-header \
		$(WAYLAND_PROTOCOLS_DATADIR)/stable/xdg-shell/xdg-shell.xml \
		$@

xdg-shell-protocol.c:
	$(WAYLAND_SCANNER) private-code \
		$(WAYLAND_PROTOCOLS_DATADIR)/stable/xdg-shell/xdg-shell.xml \
		$@

clean-local:
	-rm -f wlr-layer-shell-unstable-v1-client-protocol.h \
		wlr-layer-shell-unstable-v1-protocol.c \
		xdg-shell-client-protocol.h \
		xdg-shell-protocol.c

uninstall-hook:
	rmdir $(machdepdir) || true
