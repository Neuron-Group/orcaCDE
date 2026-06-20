/*
 * NsCDE foreign toplevel daemon for labwc backend.
 *
 * This is a Wayland client that uses wlr-foreign-toplevel-management-v1
 * protocol to track window state. It provides window tracking for the
 * task list and shell UI components.
 *
 * Writes state to windows.env for shell UI consumption.
 * Reads commands from the session command FIFO.
 *
 * This file is a part of NsCDE - Not so Common Desktop Environment
 * Author: Hegel3DReloaded
 * Licence: GPLv3
 */

#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <wayland-client.h>

/* Forward declarations for protocol-generated types */
struct zwlr_foreign_toplevel_manager_v1;
struct zwlr_foreign_toplevel_handle_v1;

/* Include generated protocol headers */
#include "wlr-foreign-toplevel-management-unstable-v1-client-protocol.h"

#define MAX_TOPLEVELS 64
#define MAX_TITLE_LEN 512
#define MAX_APP_ID_LEN 256
#define STATE_LINE_LEN 1024
#define PATH_MAX_LEN 1024

/* Toplevel state */
struct toplevel {
	struct zwlr_foreign_toplevel_handle_v1 *handle;
	char title[MAX_TITLE_LEN];
	char app_id[MAX_APP_ID_LEN];
	bool maximized;
	bool minimized;
	bool activated;
	bool fullscreen;
	bool valid;
};

/* Toplevel daemon state */
static struct {
	struct wl_display *display;
	struct wl_registry *registry;
	struct zwlr_foreign_toplevel_manager_v1 *manager;
	struct wl_seat *seat;

	struct toplevel toplevels[MAX_TOPLEVELS];
	int toplevel_count;
	char focused_title[MAX_TITLE_LEN];
	char focused_app_id[MAX_APP_ID_LEN];
	uint32_t focused_id;

	/* State files */
	char state_dir[PATH_MAX_LEN];
	char windows_env_path[PATH_MAX_LEN];
	char taskd_env_path[PATH_MAX_LEN];
	char command_fifo_path[PATH_MAX_LEN];

	/* Session FIFO for receiving commands */
	int session_fifo_fd;

	/* Running state */
	bool running;
	bool dirty;
} toplevel_state = {
	.toplevel_count = 0,
	.focused_title = "",
	.focused_app_id = "",
	.focused_id = 0,
	.seat = NULL,
	.session_fifo_fd = -1,
	.running = true,
	.dirty = true,
};

/* Find toplevel by handle */
static struct toplevel *
find_toplevel_by_handle(struct zwlr_foreign_toplevel_handle_v1 *handle)
{
	for (int i = 0; i < toplevel_state.toplevel_count; i++) {
		if (toplevel_state.toplevels[i].handle == handle &&
		    toplevel_state.toplevels[i].valid) {
			return &toplevel_state.toplevels[i];
		}
	}
	return NULL;
}

/* Find toplevel by id (index) */
static struct toplevel *
find_toplevel_by_id(uint32_t id)
{
	if (id < (uint32_t)toplevel_state.toplevel_count &&
	    toplevel_state.toplevels[id].valid) {
		return &toplevel_state.toplevels[id];
	}
	return NULL;
}

/* Add a new toplevel */
static struct toplevel *
add_toplevel(struct zwlr_foreign_toplevel_handle_v1 *handle)
{
	if (toplevel_state.toplevel_count >= MAX_TOPLEVELS) {
		fprintf(stderr, "nscde_toplevel: max toplevels reached\n");
		return NULL;
	}

	struct toplevel *tl = &toplevel_state.toplevels[toplevel_state.toplevel_count];
	tl->handle = handle;
	tl->title[0] = '\0';
	tl->app_id[0] = '\0';
	tl->maximized = false;
	tl->minimized = false;
	tl->activated = false;
	tl->fullscreen = false;
	tl->valid = true;
	toplevel_state.toplevel_count++;
	return tl;
}

/* Remove a toplevel */
static void
remove_toplevel(struct zwlr_foreign_toplevel_handle_v1 *handle)
{
	for (int i = 0; i < toplevel_state.toplevel_count; i++) {
		if (toplevel_state.toplevels[i].handle == handle) {
			toplevel_state.toplevels[i].valid = false;
			/* Shift remaining toplevels */
			for (int j = i; j < toplevel_state.toplevel_count - 1; j++) {
				toplevel_state.toplevels[j] = toplevel_state.toplevels[j + 1];
			}
			toplevel_state.toplevel_count--;
			toplevel_state.dirty = true;
			return;
		}
	}
}

/* Write windows.env state file */
static void
write_windows_env(void)
{
	FILE *f;
	char tmp_path[PATH_MAX_LEN + 4];

	snprintf(tmp_path, sizeof(tmp_path), "%s.tmp", toplevel_state.windows_env_path);
	f = fopen(tmp_path, "w");
	if (!f) {
		fprintf(stderr, "nscde_toplevel: cannot write %s: %s\n",
		    tmp_path, strerror(errno));
		return;
	}

	fprintf(f, "NSCDE_WINDOW_COUNT=%d\n", toplevel_state.toplevel_count);
	fprintf(f, "NSCDE_FOCUSED_WINDOW=%u\n", toplevel_state.focused_id);
	fprintf(f, "NSCDE_FOCUSED_TITLE=%s\n", toplevel_state.focused_title);
	fprintf(f, "NSCDE_FOCUSED_APP_ID=%s\n", toplevel_state.focused_app_id);
	fprintf(f, "NSCDE_TASKD_COMMAND_FIFO=%s\n", toplevel_state.command_fifo_path);

	/* Write per-window entries */
	for (int i = 0; i < toplevel_state.toplevel_count; i++) {
		if (toplevel_state.toplevels[i].valid) {
			fprintf(f, "NSCDE_WINDOW_%d_TITLE=%s\n", i,
			    toplevel_state.toplevels[i].title);
			fprintf(f, "NSCDE_WINDOW_%d_APP_ID=%s\n", i,
			    toplevel_state.toplevels[i].app_id);
			fprintf(f, "NSCDE_WINDOW_%d_MAXIMIZED=%d\n", i,
			    toplevel_state.toplevels[i].maximized ? 1 : 0);
			fprintf(f, "NSCDE_WINDOW_%d_MINIMIZED=%d\n", i,
			    toplevel_state.toplevels[i].minimized ? 1 : 0);
			fprintf(f, "NSCDE_WINDOW_%d_ACTIVATED=%d\n", i,
			    toplevel_state.toplevels[i].activated ? 1 : 0);
			fprintf(f, "NSCDE_WINDOW_%d_FULLSCREEN=%d\n", i,
			    toplevel_state.toplevels[i].fullscreen ? 1 : 0);
		}
	}

	fclose(f);

	/* Atomic rename */
	if (rename(tmp_path, toplevel_state.windows_env_path) != 0) {
		fprintf(stderr, "nscde_toplevel: cannot rename %s: %s\n",
		    tmp_path, strerror(errno));
	}
}

/* Write taskd.env state file */
static void
write_taskd_env(void)
{
	FILE *f;
	char tmp_path[PATH_MAX_LEN + 4];

	snprintf(tmp_path, sizeof(tmp_path), "%s.tmp", toplevel_state.taskd_env_path);
	f = fopen(tmp_path, "w");
	if (!f) {
		fprintf(stderr, "nscde_toplevel: cannot write %s: %s\n",
		    tmp_path, strerror(errno));
		return;
	}

	fprintf(f, "NSCDE_TASKD_WINDOW_COUNT=%d\n", toplevel_state.toplevel_count);
	fprintf(f, "NSCDE_TASKD_FOCUSED_ID=%u\n", toplevel_state.focused_id);
	fprintf(f, "NSCDE_TASKD_FOCUSED_TITLE=%s\n", toplevel_state.focused_title);
	fprintf(f, "NSCDE_TASKD_FOCUSED_APP_ID=%s\n", toplevel_state.focused_app_id);
	fprintf(f, "NSCDE_TASKD_COMMAND_FIFO=%s\n", toplevel_state.command_fifo_path);

	fclose(f);

	/* Atomic rename */
	if (rename(tmp_path, toplevel_state.taskd_env_path) != 0) {
		fprintf(stderr, "nscde_toplevel: cannot rename %s: %s\n",
		    tmp_path, strerror(errno));
	}
}

/* Update all state files */
static void
update_state(void)
{
	write_windows_env();
	toplevel_state.dirty = false;
}

/* Protocol callbacks for toplevel handles */
static void
toplevel_handle_title(void *data,
    struct zwlr_foreign_toplevel_handle_v1 *handle, const char *title)
{
	struct toplevel *tl = data;
	if (tl && title) {
		strncpy(tl->title, title, MAX_TITLE_LEN - 1);
		tl->title[MAX_TITLE_LEN - 1] = '\0';
		toplevel_state.dirty = true;
	}
}

static void
toplevel_handle_app_id(void *data,
    struct zwlr_foreign_toplevel_handle_v1 *handle, const char *app_id)
{
	struct toplevel *tl = data;
	if (tl && app_id) {
		strncpy(tl->app_id, app_id, MAX_APP_ID_LEN - 1);
		tl->app_id[MAX_APP_ID_LEN - 1] = '\0';
		toplevel_state.dirty = true;
	}
}

static void
toplevel_handle_output_enter(void *data,
    struct zwlr_foreign_toplevel_handle_v1 *handle,
    struct wl_output *output)
{
	/* We don't track output associations yet */
	(void)data;
	(void)handle;
	(void)output;
}

static void
toplevel_handle_output_leave(void *data,
    struct zwlr_foreign_toplevel_handle_v1 *handle,
    struct wl_output *output)
{
	/* We don't track output associations yet */
	(void)data;
	(void)handle;
	(void)output;
}

static void
toplevel_handle_state(void *data,
    struct zwlr_foreign_toplevel_handle_v1 *handle,
    struct wl_array *state)
{
	struct toplevel *tl = data;
	if (!tl) {
		return;
	}

	tl->maximized = false;
	tl->minimized = false;
	tl->activated = false;
	tl->fullscreen = false;

	uint32_t *entry;
	wl_array_for_each(entry, state) {
		switch (*entry) {
		case ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_MAXIMIZED:
			tl->maximized = true;
			break;
		case ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_MINIMIZED:
			tl->minimized = true;
			break;
		case ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_ACTIVATED:
			tl->activated = true;
			break;
		case ZWLR_FOREIGN_TOPLEVEL_HANDLE_V1_STATE_FULLSCREEN:
			tl->fullscreen = true;
			break;
		}
	}

	/* Update focused window if this toplevel is activated */
	if (tl->activated) {
		/* Find the id (index) of this toplevel */
		for (int i = 0; i < toplevel_state.toplevel_count; i++) {
			if (&toplevel_state.toplevels[i] == tl) {
				toplevel_state.focused_id = (uint32_t)i;
				break;
			}
		}
		strncpy(toplevel_state.focused_title, tl->title,
		    MAX_TITLE_LEN - 1);
		toplevel_state.focused_title[MAX_TITLE_LEN - 1] = '\0';
		strncpy(toplevel_state.focused_app_id, tl->app_id,
		    MAX_APP_ID_LEN - 1);
		toplevel_state.focused_app_id[MAX_APP_ID_LEN - 1] = '\0';
	}

	toplevel_state.dirty = true;
}

static void
toplevel_handle_done(void *data,
    struct zwlr_foreign_toplevel_handle_v1 *handle)
{
	/* All changes have been sent, update state */
	(void)data;
	(void)handle;

	if (toplevel_state.dirty) {
		update_state();
	}
}

static void
toplevel_handle_closed(void *data,
    struct zwlr_foreign_toplevel_handle_v1 *handle)
{
	struct toplevel *tl = data;
	if (tl) {
		remove_toplevel(handle);
		zwlr_foreign_toplevel_handle_v1_destroy(handle);
	}
}

static void
toplevel_handle_parent(void *data,
    struct zwlr_foreign_toplevel_handle_v1 *handle,
    struct zwlr_foreign_toplevel_handle_v1 *parent)
{
	/* We don't track parent relationships yet */
	(void)data;
	(void)handle;
	(void)parent;
}

static const struct zwlr_foreign_toplevel_handle_v1_listener toplevel_listener = {
	.title = toplevel_handle_title,
	.app_id = toplevel_handle_app_id,
	.output_enter = toplevel_handle_output_enter,
	.output_leave = toplevel_handle_output_leave,
	.state = toplevel_handle_state,
	.done = toplevel_handle_done,
	.closed = toplevel_handle_closed,
	.parent = toplevel_handle_parent,
};

/* Manager callbacks */
static void
manager_handle_toplevel(void *data,
    struct zwlr_foreign_toplevel_manager_v1 *manager,
    struct zwlr_foreign_toplevel_handle_v1 *handle)
{
	struct toplevel *tl = add_toplevel(handle);
	if (tl) {
		zwlr_foreign_toplevel_handle_v1_add_listener(handle,
		    &toplevel_listener, tl);
	}
}

static void
manager_handle_finished(void *data,
    struct zwlr_foreign_toplevel_manager_v1 *manager)
{
	(void)data;
	(void)manager;

	toplevel_state.running = false;
}

static const struct zwlr_foreign_toplevel_manager_v1_listener manager_listener = {
	.toplevel = manager_handle_toplevel,
	.finished = manager_handle_finished,
};

/* Registry callbacks */
static void
registry_global(void *data, struct wl_registry *registry, uint32_t name,
    const char *interface, uint32_t version)
{
	(void)data;

	if (strcmp(interface, zwlr_foreign_toplevel_manager_v1_interface.name) == 0) {
		toplevel_state.manager = wl_registry_bind(registry, name,
		    &zwlr_foreign_toplevel_manager_v1_interface, 1);
		zwlr_foreign_toplevel_manager_v1_add_listener(toplevel_state.manager,
		    &manager_listener, NULL);
	} else if (strcmp(interface, wl_seat_interface.name) == 0) {
		if (!toplevel_state.seat) {
			toplevel_state.seat = wl_registry_bind(registry, name,
			    &wl_seat_interface, 1);
		}
	}
}

static void
registry_global_remove(void *data, struct wl_registry *registry,
    uint32_t name)
{
	/* We don't need to handle global removal */
	(void)data;
	(void)registry;
	(void)name;
}

static const struct wl_registry_listener registry_listener = {
	.global = registry_global,
	.global_remove = registry_global_remove,
};

/* Process commands from session FIFO */
static void
process_fifo_commands(void)
{
	char buf[512];
	ssize_t n;

	/* Non-blocking read from FIFO */
	n = read(toplevel_state.session_fifo_fd, buf, sizeof(buf) - 1);
	if (n <= 0) {
		if (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
			fprintf(stderr, "nscde_toplevel: FIFO read error: %s\n",
			    strerror(errno));
		}
		return;
	}

	buf[n] = '\0';

	/* Process each line */
	char *line = buf;
	char *next_line;

	while (line && *line) {
		next_line = strchr(line, '\n');
		if (next_line) {
			*next_line = '\0';
			next_line++;
		}

		/* Parse command: activate, close, minimize, restore */
		if (strncmp(line, "activate:", 9) == 0) {
			uint32_t id = (uint32_t)atoi(line + 9);
			struct toplevel *tl = find_toplevel_by_id(id);
			if (tl && tl->handle) {
				if (toplevel_state.seat) {
					zwlr_foreign_toplevel_handle_v1_activate(
					    tl->handle, toplevel_state.seat);
				} else {
					fprintf(stderr,
					    "nscde_toplevel: no seat for activate\n");
				}
			}
		} else if (strncmp(line, "close:", 6) == 0) {
			uint32_t id = (uint32_t)atoi(line + 6);
			struct toplevel *tl = find_toplevel_by_id(id);
			if (tl && tl->handle) {
				zwlr_foreign_toplevel_handle_v1_close(tl->handle);
			}
		} else if (strncmp(line, "minimize:", 9) == 0) {
			uint32_t id = (uint32_t)atoi(line + 9);
			struct toplevel *tl = find_toplevel_by_id(id);
			if (tl && tl->handle) {
				zwlr_foreign_toplevel_handle_v1_set_minimized(
				    tl->handle);
			}
		} else if (strncmp(line, "restore:", 8) == 0) {
			uint32_t id = (uint32_t)atoi(line + 8);
			struct toplevel *tl = find_toplevel_by_id(id);
			if (tl && tl->handle) {
				zwlr_foreign_toplevel_handle_v1_unset_minimized(
				    tl->handle);
				if (toplevel_state.seat) {
					zwlr_foreign_toplevel_handle_v1_activate(
					    tl->handle, toplevel_state.seat);
				}
			}
		} else if (strncmp(line, "maximize:", 9) == 0) {
			uint32_t id = (uint32_t)atoi(line + 9);
			struct toplevel *tl = find_toplevel_by_id(id);
			if (tl && tl->handle) {
				zwlr_foreign_toplevel_handle_v1_set_maximized(
				    tl->handle);
			}
		}

		line = next_line;
	}
}

/* Initialize state directory paths */
static void
init_paths(void)
{
	const char *xdg_cache = getenv("XDG_CACHE_HOME");
	char cache_dir[512];

	if (xdg_cache) {
		snprintf(cache_dir, sizeof(cache_dir), "%s", xdg_cache);
	} else {
		const char *home = getenv("HOME");
		if (!home) {
			home = "/tmp";
		}
		snprintf(cache_dir, sizeof(cache_dir), "%s/.cache", home);
	}

	snprintf(toplevel_state.state_dir, sizeof(toplevel_state.state_dir),
	    "%s/nscde-stage1", cache_dir);
	snprintf(toplevel_state.windows_env_path, sizeof(toplevel_state.windows_env_path),
	    "%s/windows.env", toplevel_state.state_dir);
	snprintf(toplevel_state.taskd_env_path, sizeof(toplevel_state.taskd_env_path),
	    "%s/taskd.env", toplevel_state.state_dir);
	snprintf(toplevel_state.command_fifo_path, sizeof(toplevel_state.command_fifo_path),
	    "%s/topleveld.fifo", toplevel_state.state_dir);
}

/* Ensure state directory exists */
static int
ensure_state_dir(void)
{
	struct stat st;

	if (stat(toplevel_state.state_dir, &st) == 0) {
		return 0;
	}

	if (mkdir(toplevel_state.state_dir, 0755) != 0) {
		fprintf(stderr, "nscde_toplevel: cannot create %s: %s\n",
		    toplevel_state.state_dir, strerror(errno));
		return -1;
	}

	return 0;
}

/* Ensure toplevel command FIFO exists */
static int
ensure_command_fifo(void)
{
	struct stat st;

	if (stat(toplevel_state.command_fifo_path, &st) == 0) {
		if (S_ISFIFO(st.st_mode)) {
			return 0;
		}
		if (unlink(toplevel_state.command_fifo_path) != 0) {
			fprintf(stderr, "nscde_toplevel: cannot remove %s: %s\n",
			    toplevel_state.command_fifo_path, strerror(errno));
			return -1;
		}
	} else if (errno != ENOENT) {
		fprintf(stderr, "nscde_toplevel: cannot stat %s: %s\n",
		    toplevel_state.command_fifo_path, strerror(errno));
		return -1;
	}

	if (mkfifo(toplevel_state.command_fifo_path, 0600) != 0 &&
	    errno != EEXIST) {
		fprintf(stderr, "nscde_toplevel: cannot create FIFO %s: %s\n",
		    toplevel_state.command_fifo_path, strerror(errno));
		return -1;
	}

	return 0;
}

/* Open session FIFO for reading (non-blocking) */
static int
open_session_fifo(void)
{
	int fd;

	if (ensure_command_fifo() != 0) {
		return -1;
	}

	/* Open FIFO in non-blocking mode */
	fd = open(toplevel_state.command_fifo_path, O_RDONLY | O_NONBLOCK);
	if (fd < 0) {
		fprintf(stderr, "nscde_toplevel: cannot open FIFO %s: %s\n",
		    toplevel_state.command_fifo_path, strerror(errno));
		return -1;
	}

	return fd;
}

/* Signal handler */
static volatile sig_atomic_t caught_signal = 0;

static void
signal_handler(int sig)
{
	caught_signal = sig;
}

/* Setup signal handlers */
static void
setup_signals(void)
{
	struct sigaction sa;

	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = signal_handler;
	sigemptyset(&sa.sa_mask);
	sa.sa_flags = SA_RESTART;

	sigaction(SIGINT, &sa, NULL);
	sigaction(SIGTERM, &sa, NULL);
	sigaction(SIGHUP, &sa, NULL);
}

/* Print usage */
static void
usage(const char *prog)
{
	fprintf(stderr, "Usage: %s [options]\n", prog);
	fprintf(stderr, "Options:\n");
	fprintf(stderr, "  -h    Show this help\n");
	fprintf(stderr, "  -v    Show version\n");
}

int
main(int argc, char *argv[])
{
	int opt;
	struct pollfd fds[2];
	int nfds;

	/* Parse arguments */
	while ((opt = getopt(argc, argv, "hv")) != -1) {
		switch (opt) {
		case 'h':
			usage(argv[0]);
			return 0;
		case 'v':
			printf("nscde_toplevel (NsCDE) 1.0\n");
			return 0;
		default:
			usage(argv[0]);
			return 1;
		}
	}

	/* Initialize paths */
	init_paths();

	/* Ensure state directory exists */
	if (ensure_state_dir() != 0) {
		return 1;
	}

	/* Setup signal handlers */
	setup_signals();

	/* Connect to Wayland display */
	toplevel_state.display = wl_display_connect(NULL);
	if (!toplevel_state.display) {
		fprintf(stderr, "nscde_toplevel: cannot connect to Wayland display\n");
		return 1;
	}

	/* Get registry and bind to foreign-toplevel-manager */
	toplevel_state.registry = wl_display_get_registry(toplevel_state.display);
	if (!toplevel_state.registry) {
		fprintf(stderr, "nscde_toplevel: cannot get registry\n");
		wl_display_disconnect(toplevel_state.display);
		return 1;
	}

	wl_registry_add_listener(toplevel_state.registry, &registry_listener, NULL);

	/* Initial roundtrip to get globals */
	if (wl_display_roundtrip(toplevel_state.display) < 0) {
		fprintf(stderr, "nscde_toplevel: roundtrip failed\n");
		wl_display_disconnect(toplevel_state.display);
		return 1;
	}

	if (!toplevel_state.manager) {
		fprintf(stderr, "nscde_toplevel: wlr-foreign-toplevel-manager not available\n");
		wl_display_disconnect(toplevel_state.display);
		return 1;
	}

	/* Second roundtrip to get initial toplevel state */
	if (wl_display_roundtrip(toplevel_state.display) < 0) {
		fprintf(stderr, "nscde_toplevel: roundtrip failed\n");
		wl_display_disconnect(toplevel_state.display);
		return 1;
	}

	/* Open session FIFO */
	toplevel_state.session_fifo_fd = open_session_fifo();

	/* Write initial state */
	update_state();

	/* Main event loop */
	while (toplevel_state.running) {
		/* Setup poll fds */
		nfds = 0;

		/* Wayland display fd */
		fds[nfds].fd = wl_display_get_fd(toplevel_state.display);
		fds[nfds].events = POLLIN;
		nfds++;

		/* Session FIFO fd (if open) */
		if (toplevel_state.session_fifo_fd >= 0) {
			fds[nfds].fd = toplevel_state.session_fifo_fd;
			fds[nfds].events = POLLIN;
			nfds++;
		}

		/* Dispatch pending Wayland events */
		while (wl_display_prepare_read(toplevel_state.display) != 0) {
			if (wl_display_dispatch_pending(toplevel_state.display) < 0) {
				fprintf(stderr, "nscde_toplevel: dispatch pending failed\n");
				toplevel_state.running = false;
				break;
			}
		}

		if (!toplevel_state.running) {
			break;
		}

		/* Flush outgoing events */
		if (wl_display_flush(toplevel_state.display) < 0) {
			fprintf(stderr, "nscde_toplevel: flush failed\n");
			toplevel_state.running = false;
			break;
		}

		/* Poll for events */
		int ret = poll(fds, nfds, 1000);
		if (ret < 0) {
			if (errno == EINTR) {
				if (caught_signal) {
					fprintf(stderr, "nscde_toplevel: caught signal %d\n",
					    caught_signal);
					toplevel_state.running = false;
				}
				wl_display_cancel_read(toplevel_state.display);
				continue;
			}
			fprintf(stderr, "nscde_toplevel: poll error: %s\n",
			    strerror(errno));
			wl_display_cancel_read(toplevel_state.display);
			break;
		}

		if (ret == 0) {
			/* Timeout - check for state updates */
			wl_display_cancel_read(toplevel_state.display);
			if (toplevel_state.dirty) {
				update_state();
			}
			continue;
		}

		/* Handle Wayland events */
		if (fds[0].revents & POLLIN) {
			if (wl_display_read_events(toplevel_state.display) < 0) {
				fprintf(stderr, "nscde_toplevel: read events failed\n");
				toplevel_state.running = false;
				break;
			}
			if (wl_display_dispatch_pending(toplevel_state.display) < 0) {
				fprintf(stderr, "nscde_toplevel: dispatch failed\n");
				toplevel_state.running = false;
				break;
			}
		} else {
			wl_display_cancel_read(toplevel_state.display);
		}

		/* Handle FIFO commands */
		if (nfds > 1 && (fds[1].revents & POLLIN)) {
			process_fifo_commands();
		}

		/* Update state if dirty */
		if (toplevel_state.dirty) {
			update_state();
		}
	}

	/* Cleanup */
	if (toplevel_state.session_fifo_fd >= 0) {
		close(toplevel_state.session_fifo_fd);
	}

	if (toplevel_state.manager) {
		zwlr_foreign_toplevel_manager_v1_destroy(toplevel_state.manager);
	}

	if (toplevel_state.seat) {
		wl_seat_release(toplevel_state.seat);
	}

	if (toplevel_state.registry) {
		wl_registry_destroy(toplevel_state.registry);
	}

	if (toplevel_state.display) {
		wl_display_disconnect(toplevel_state.display);
	}

	return 0;
}
