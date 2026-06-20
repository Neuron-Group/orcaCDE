/*
 * NsCDE layer-shell front panel for labwc backend.
 *
 * This is a Wayland client that uses zwlr_layer_shell_v1 to create a
 * proper panel surface with exclusive zone reservation. It replaces the
 * stage-one PyQt5 placeholder with a native C layer-shell implementation.
 *
 * Prefers runtime socket query/subscribe for panel state when available,
 * with state-file/inotify fallback during the staged transition.
 * Writes workspace switch commands through the runtime control path first,
 * then falls back to the pager FIFO when needed.
 *
 * This file is a part of NsCDE - Not so Common Desktop Environment
 * Author: Hegel3DReloaded
 * Licence: GPLv3
 */

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <poll.h>
#include <signal.h>
#include <sys/signalfd.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/inotify.h>
#include <sys/timerfd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include <cairo.h>
#include <pango/pangocairo.h>

#include "../nscde_wayland_common/panel-layout-contract.h"
#include "../nscde_wayland_common/runtime-client.h"
#include "nscde-pixel-icon.h"
#include "pool-buffer.h"
#include "wlr-layer-shell-unstable-v1-client-protocol.h"

#define MAX_WORKSPACES 32
#define MAX_LAUNCHERS 16
#define MAX_SUBPANELS 20
#define MAX_SUBPANEL_ENTRIES 32
#define MAX_APPLETS 8
#define MAX_NAME_LEN 256
#define STATE_LINE_LEN 1024
#define PATH_MAX_LEN 1024

#ifndef BTN_LEFT
#define BTN_LEFT 0x110
#endif

#ifndef BTN_RIGHT
#define BTN_RIGHT 0x111
#endif

#ifndef BTN_MIDDLE
#define BTN_MIDDLE 0x112
#endif

/* CDE palette indices (0-based array, 1-based CDE indices) */
struct cde_palette {
	double bg[4];    /* 1: Background */
	double fg[4];    /* 2: Foreground */
	double hi[4];    /* 3: Top shadow (highlight) */
	double sh[4];    /* 4: Bottom shadow (shadow) */
	double sel[4];   /* 5: Select */
	double acc[4];   /* 6: Accent */
	double sbg[4];   /* 7: Secondary bg */
	double sfg[4];   /* 8: Secondary fg */
};

struct motif_palette_slots {
	double color[8][4];
};

/* Applet type */
enum applet_type {
	APPLET_CLOCK,
	APPLET_DATE,
	APPLET_MAIL,
	APPLET_LOAD,
	APPLET_UNKNOWN,
};

/* Workspace button geometry */
struct ws_button {
	char name[MAX_NAME_LEN];
	int x;
	int y;
	int width;
	int height;
	bool active;
};

/* Launcher button geometry */
struct launcher_button {
	char module[MAX_NAME_LEN];
	char label[MAX_NAME_LEN];
	char command[PATH_MAX_LEN];
	enum applet_type content_type;
	bool show_label;
	int x;
	int width;
	int icon_size;
	int trigger_y;
	int trigger_h;
	int body_y;
	int body_h;
	int subpanel_idx;  /* -1 if no subpanel, 0-19 if mapped */
};

struct section_rect {
	int x;
	int y;
	int w;
	int h;
};

struct panel_layout_model {
	struct section_rect left_handle;
	struct section_rect left_bank;
	struct section_rect center;
	struct section_rect right_bank;
	struct section_rect right_handle;
	struct section_rect bottom_strip;
	struct section_rect left_handle_button;
	struct section_rect left_handle_grip;
	struct section_rect right_handle_button;
	struct section_rect right_handle_grip;
	struct section_rect wsm_lock_slot;
	struct section_rect wsm_pgm_slot;
	struct section_rect wsm_grid;
	struct section_rect wsm_load_slot;
	struct section_rect wsm_exit_slot;
	struct section_rect wsm_lock_icon;
	struct section_rect wsm_pgm_icon;
	struct section_rect wsm_exit_icon;
};

enum panel_hit_role {
	PANEL_HIT_NONE,
	PANEL_HIT_SUBPANEL_ENTRY,
	PANEL_HIT_LEFT_MENU_BUTTON,
	PANEL_HIT_LEFT_HANDLE,
	PANEL_HIT_RIGHT_ICONIFY_BUTTON,
	PANEL_HIT_RIGHT_HANDLE,
	PANEL_HIT_WSM_LOCK,
	PANEL_HIT_WSM_PGM,
	PANEL_HIT_WSM_LOAD,
	PANEL_HIT_WSM_EXIT,
	PANEL_HIT_LAUNCHER_TRIGGER,
	PANEL_HIT_LAUNCHER_BODY,
	PANEL_HIT_RIGHT_LAUNCHER_TRIGGER,
	PANEL_HIT_RIGHT_LAUNCHER_BODY,
	PANEL_HIT_APPLET,
	PANEL_HIT_WORKSPACE,
};

struct panel_hit_result {
	enum panel_hit_role role;
	int index;
	int sub_index;
};

/* Subpanel entry */
struct subpanel_entry {
	char title[MAX_NAME_LEN];
	char type[MAX_NAME_LEN];
	char icon[PATH_MAX_LEN];
	char command[PATH_MAX_LEN];
};

/* Subpanel definition */
struct subpanel_def {
	char name[MAX_NAME_LEN];
	int width;
	bool enabled;
	int entry_count;
	struct subpanel_entry entries[MAX_SUBPANEL_ENTRIES];
};

/* Subpanel surface state (one per open subpanel) */
struct subpanel_surface {
	int subpanel_idx;             /* index into subpanels[] */
	struct wl_surface *surface;
	struct zwlr_layer_surface_v1 *layer_surface;
	struct pool_buffer buffers[2];
	struct pool_buffer *current_buffer;
	uint32_t width;
	uint32_t height;
	int32_t scale;
	bool configured;
	bool open;
};

/* Applet slot in the right area */
struct applet_slot {
	enum applet_type type;
	bool is_launcher;
	char name[MAX_NAME_LEN];
	char label[MAX_NAME_LEN];
	int x;
	int width;
	int height;
	int trigger_y;
	int trigger_h;
	int body_y;
	int body_h;
	int subpanel_idx;
	char command[PATH_MAX_LEN];
};

/* Applet live state */
struct applet_state {
	/* Clock */
	int clock_hour;
	int clock_minute;
	int clock_second;
	/* Date */
	char date_month[8];
	char date_day[8];
	/* Mail */
	bool mail_has_new;
	int mail_count;
	/* Load */
	double load_1min;
	int load_bar_pct;  /* 0-100 */
};

/* Panel state */
static struct {
	struct wl_display *display;
	struct wl_registry *registry;
	struct wl_compositor *compositor;
	struct wl_shm *shm;
	struct wl_seat *seat;
	struct wl_surface *surface;
	struct zwlr_layer_shell_v1 *layer_shell;
	struct zwlr_layer_surface_v1 *layer_surface;

	uint32_t width;
	uint32_t height;
	int32_t scale;
	struct pool_buffer buffers[2];
	struct pool_buffer *current_buffer;

	/* Palette */
	struct motif_palette_slots palette_slots;
	struct cde_palette palette;
	struct cde_palette fp_button_palette;
	double fp_gap_light[4];
	double fp_gap_dark[4];
	int fp_variant;

	/* Workspace state */
	struct ws_button workspaces[MAX_WORKSPACES];
	int workspace_count;
	char current_workspace[MAX_NAME_LEN];

	/* Launcher state */
	struct launcher_button launchers[MAX_LAUNCHERS];
	int launcher_count;
	char launcher_commands[MAX_LAUNCHERS][PATH_MAX_LEN];

	/* Subpanel definitions */
	struct subpanel_def subpanels[MAX_SUBPANELS];
	int subpanel_count;

	/* Active subpanel surface (-1 = none) */
	int active_subpanel;
	struct subpanel_surface sp_surface;

	/* Applet slots and live state */
	struct applet_slot applets[MAX_APPLETS];
	int applet_count;
	struct applet_state applet_live;
	struct panel_layout_model layout_model;

	/* Subpanel file path */
	char subpanel_env_path[PATH_MAX_LEN + 64];

	/* Info labels */
	char left_label[MAX_NAME_LEN];
	char right_label[MAX_NAME_LEN * 2];

	/* State file paths */
	char panel_env_path[PATH_MAX_LEN + 64];
	char workspaces_env_path[PATH_MAX_LEN + 64];
	char panel_layout_env_path[PATH_MAX_LEN + 64];
	char state_dir[PATH_MAX_LEN + 16];
	char pager_fifo_path[PATH_MAX_LEN];
	struct nscde_runtime_subscription runtime_subscription;
	bool runtime_active;

	struct nscde_panel_layout_contract layout;
	int layout_left_area_width;   /* computed from launcher geometry */

	/* Running state */
	bool running;
	bool configured;
	bool dirty;
	bool frame_pending;
	struct nscde_pixel_icon_context pixel_icons;
} panel = {
	.width = 1024,
	.height = 79,
	.scale = 1,
	.workspace_count = 0,
	.current_workspace = "",
	.launcher_count = 0,
	.left_label = "NsCDE",
	.right_label = "labwc",
	.runtime_subscription = {
		.fd = -1,
	},
	.runtime_active = false,
	.layout = NSCDE_PANEL_LAYOUT_CONTRACT_DEFAULTS,
	.layout_left_area_width = 0,  /* computed in rebuild_launchers */
	.active_subpanel = -1,
	.running = true,
	.configured = false,
	.dirty = true,
};

#define layout_height layout.height
#define layout_border_width layout.border_width
#define layout_edge layout.edge
#define layout_button_min_width layout.button_min_width
#define layout_button_padding layout.button_padding
#define layout_button_gap layout.button_gap
#define layout_margin layout.margin
#define layout_bevel_width layout.bevel_width
#define layout_right_area_width layout.right_area_width
#define layout_ws_recess_height layout.ws_recess_height
#define layout_launcher_unit_width layout.launcher_unit_width
#define layout_launcher_icon_size layout.launcher_icon_size
#define layout_launcher_gap layout.launcher_gap
#define layout_font layout.font
#define layout_left_modules layout.left_modules
#define layout_right_modules layout.right_modules
#define layout_applet_unit_width layout.applet_unit_width
#define layout_left_handle_width layout.left_handle_width
#define layout_right_handle_width layout.right_handle_width
#define layout_trigger_height layout.trigger_height
#define layout_body_height layout.body_height
#define layout_bottom_strip_height layout.bottom_strip_height
#define layout_section_separator_width layout.section_separator_width
#define layout_applet_gap layout.applet_gap
#define layout_desk_count layout.desk_count
#define layout_wsm_width layout.wsm_width
#define layout_wsm_lock_width layout.wsm_lock_width
#define layout_wsm_exit_width layout.wsm_exit_width
#define layout_wsm_buttons_width layout.wsm_buttons_width
#define layout_left_launcher_count layout.left_launcher_count
#define layout_right_launcher_count layout.right_launcher_count
#define layout_left_bank_width layout.left_bank_width
#define layout_right_bank_width layout.right_bank_width
#define layout_center_section_x layout.center_section_x
#define layout_center_section_width layout.center_section_width
#define layout_wsm_inner_pad layout.wsm_inner_pad
#define layout_wsm_side_width layout.wsm_side_width
#define layout_wsm_utility_width layout.wsm_utility_width
#define layout_wsm_section_gap layout.wsm_section_gap
#define layout_wsm_grid_vpad layout.wsm_grid_vpad
#define layout_wsm_lock_height layout.wsm_lock_height
#define layout_wsm_load_inset_top layout.wsm_load_inset_top
#define layout_wsm_load_inset_side layout.wsm_load_inset_side
#define layout_wsm_load_height layout.wsm_load_height
#define layout_wsm_exit_height layout.wsm_exit_height
#define layout_wsm_exit_inset_bottom layout.wsm_exit_inset_bottom
#define layout_wsm_utility_inset_side layout.wsm_utility_inset_side
#define layout_scale layout.scale
#define layout_version layout.version
#define layout_source layout.source
#define layout_ws_font layout.ws_font
#define layout_applet_date_font layout.applet_date_font
#define layout_applet_mail_font layout.applet_mail_font
#define layout_applet_clock_size layout.applet_clock_size
#define layout_applet_date_size layout.applet_date_size
#define layout_applet_mail_size layout.applet_mail_size
#define layout_applet_load_width layout.applet_load_width
#define layout_applet_load_height layout.applet_load_height
#define layout_subpanel_entry_height layout.subpanel_entry_height
#define layout_subpanel_icon_size layout.subpanel_icon_size
#define layout_subpanel_title_height layout.subpanel_title_height
#define layout_subpanel_padding layout.subpanel_padding

/* Default CDE-like palette (Charcoal-inspired) */
static const struct cde_palette default_palette = {
	.bg  = {0.718, 0.757, 0.792, 1.0},  /* #b7c1ca */
	.fg  = {0.063, 0.063, 0.063, 1.0},  /* #101010 */
	.hi  = {0.541, 0.608, 0.667, 1.0},  /* #8a9baa */
	.sh  = {0.310, 0.349, 0.392, 1.0},  /* #4f5964 */
	.sel = {0.208, 0.365, 0.518, 1.0},  /* #355d84 */
	.acc = {0.208, 0.365, 0.518, 1.0},  /* #355d84 */
	.sbg = {0.420, 0.467, 0.522, 1.0},  /* #6b7785 */
	.sfg = {0.906, 0.906, 0.906, 1.0},  /* #e7e7e7 */
};

static const struct motif_palette_slots default_palette_slots = {
	.color = {
		{ 0.718, 0.757, 0.792, 1.0 },
		{ 0.063, 0.063, 0.063, 1.0 },
		{ 0.541, 0.608, 0.667, 1.0 },
		{ 0.310, 0.349, 0.392, 1.0 },
		{ 0.208, 0.365, 0.518, 1.0 },
		{ 0.208, 0.365, 0.518, 1.0 },
		{ 0.420, 0.467, 0.522, 1.0 },
		{ 0.906, 0.906, 0.906, 1.0 },
	},
};

enum {
	FD_WAYLAND,
	FD_RUNTIME,
	FD_INOTIFY,
	FD_TIMER,
	FD_SIGNAL,
	NR_FDS,
};

static struct pollfd pollfds[NR_FDS];
static struct wl_pointer *panel_pointer;
static struct wl_surface *pointer_focus_surface;
typedef void (*state_contents_parser_fn)(const char *contents);

/* Forward declarations */
static void rebuild_launchers(void);
static void rebuild_applets(void);
static void execute_launcher_command(const char *command);
static void recompute_panel_dimensions(void);
static bool lookup_panel_module(const char *name, char *label, size_t label_size,
	char *command, size_t command_size, enum applet_type *content_type,
	bool *show_label);
static void render_applet_clock(cairo_t *cr, int cx, int cy, int size,
	const struct cde_palette *pal);
static void render_applet_date(cairo_t *cr, PangoLayout *layout, int x, int y,
	int w, int h, const struct cde_palette *pal);
static void render_applet_mail(cairo_t *cr, int x, int y, int w, int h,
	const struct cde_palette *pal);
static void render_applet_load(cairo_t *cr, int x, int y, int w, int h,
	const struct cde_palette *pal);
static void parse_subpanel_env_file(void);
static void open_subpanel(int sp_idx);
static void close_subpanel(void);
static void render_subpanel_surface(void);
static void compute_panel_layout_model(struct panel_layout_model *model);
static struct panel_hit_result hit_test_panel(int x, int y);
static struct panel_hit_result hit_test_subpanel(int x, int y);
static void dispatch_panel_hit(const struct panel_hit_result *hit, uint32_t button);
static void render_and_commit(void);
static int right_launcher_subpanel_index(int launcher_idx);

static void
request_render(void)
{
	if (!panel.dirty) {
		return;
	}
	if (!panel.configured || !panel.running || panel.frame_pending) {
		return;
	}
	render_and_commit();
	panel.dirty = false;
}
static void send_workspace_switch(const char *name);
static int scale_metric(int value);
static PangoFontDescription *make_pixel_font_description(const char *spec);
static PangoFontDescription *make_scaled_font_description(const char *spec);
static void recalculate_panel_palettes(void);
static void copy_rgba(double dst[4], const double src[4]);
static void dispatch_wsm_slot_action(enum panel_hit_role role, uint32_t button);
static void dispatch_panel_chrome_action(enum panel_hit_role role, uint32_t button);
static char *read_text_file(const char *path);
static char *duplicate_text(const char *text);
static void parse_env_contents(const char *contents);
static void parse_workspaces_env_contents(const char *contents);
static void parse_subpanel_env_contents(const char *contents);
static void parse_layout_env_contents(const char *contents);
static void parse_all_state_files(void);
static bool query_runtime_topic_and_parse(const char *topic,
	state_contents_parser_fn parser);
static void sync_state_from_best_source(void);
static bool setup_runtime_subscription(void);
static void teardown_runtime_subscription(void);
static void apply_runtime_frame(const struct nscde_runtime_frame *frame);
static void handle_runtime_subscription(void);
static void refresh_state_transport(void);

/* ---- Color parsing ---- */

static bool
parse_hex_color(const char *hex, double out[4])
{
	if (!hex || hex[0] != '#' || strlen(hex) != 7) {
		return false;
	}
	unsigned int r, g, b;
	if (sscanf(hex + 1, "%02x%02x%02x", &r, &g, &b) != 3) {
		return false;
	}
	out[0] = r / 255.0;
	out[1] = g / 255.0;
	out[2] = b / 255.0;
	out[3] = 1.0;
	return true;
}

static double
motif_brightness(const double color[4])
{
	double red = color[0];
	double green = color[1];
	double blue = color[2];
	double intensity = (red + green + blue) / 3.0;
	double luminosity = (0.30 * red) + (0.59 * green) + (0.11 * blue);
	double maxv = red;
	double minv = red;
	double light;

	if (green > maxv) {
		maxv = green;
	}
	if (blue > maxv) {
		maxv = blue;
	}
	if (green < minv) {
		minv = green;
	}
	if (blue < minv) {
		minv = blue;
	}

	light = (minv + maxv) / 2.0;
	return ((intensity * 75.0) + (light * 0.0) + (luminosity * 25.0)) / 100.0;
}

static void
motif_generate_colorset(const double bg[4], struct cde_palette *out)
{
	double brightness = motif_brightness(bg);
	double fg[4] = { 1.0, 1.0, 1.0, 1.0 };
	double sel[4];
	double bs[4];
	double ts[4];
	double f_sel = 0.15;
	double f_bs;
	double f_ts;

	memcpy(out->bg, bg, sizeof(double) * 4);
	if (brightness > 0.70) {
		fg[0] = 0.0;
		fg[1] = 0.0;
		fg[2] = 0.0;
	}

	if (brightness < 0.20) {
		f_bs = 0.30;
		f_ts = 0.50;
		for (int i = 0; i < 3; i++) {
			sel[i] = bg[i] + f_sel * (1.0 - bg[i]);
			bs[i] = bg[i] + f_bs * (1.0 - bg[i]);
			ts[i] = bg[i] + f_ts * (1.0 - bg[i]);
		}
	} else if (brightness > 0.93) {
		f_bs = 0.40;
		f_ts = 0.20;
		for (int i = 0; i < 3; i++) {
			sel[i] = bg[i] - (bg[i] * f_sel);
			bs[i] = bg[i] - (bg[i] * f_bs);
			ts[i] = bg[i] - (bg[i] * f_ts);
		}
	} else {
		f_bs = 0.60 + (brightness * (0.40 - 0.60));
		f_ts = 0.50 + (brightness * (0.60 - 0.50));
		for (int i = 0; i < 3; i++) {
			sel[i] = bg[i] - (bg[i] * f_sel);
			bs[i] = bg[i] - (bg[i] * f_bs);
			ts[i] = bg[i] + f_ts * (1.0 - bg[i]);
		}
	}

	for (int i = 0; i < 3; i++) {
		fg[i] = fmax(0.0, fmin(1.0, fg[i]));
		sel[i] = fmax(0.0, fmin(1.0, sel[i]));
		bs[i] = fmax(0.0, fmin(1.0, bs[i]));
		ts[i] = fmax(0.0, fmin(1.0, ts[i]));
	}
	fg[3] = sel[3] = bs[3] = ts[3] = 1.0;

	memcpy(out->fg, fg, sizeof(double) * 4);
	memcpy(out->hi, ts, sizeof(double) * 4);
	memcpy(out->sh, bs, sizeof(double) * 4);
	memcpy(out->sel, sel, sizeof(double) * 4);
	memcpy(out->acc, sel, sizeof(double) * 4);
	memcpy(out->sbg, bg, sizeof(double) * 4);
	memcpy(out->sfg, fg, sizeof(double) * 4);
}

static void
recalculate_panel_palettes(void)
{
	int fp_index = (panel.fp_variant == 5) ? 4 : 7;

	if (fp_index < 0 || fp_index > 7) {
		fp_index = 7;
	}
	motif_generate_colorset(panel.palette_slots.color[0], &panel.palette);
	motif_generate_colorset(panel.palette_slots.color[fp_index],
		&panel.fp_button_palette);
	copy_rgba(panel.fp_gap_light, panel.palette.hi);
	copy_rgba(panel.fp_gap_dark, panel.palette.sh);
}

/* ---- Env file parsing ---- */

static void
parse_env_contents(const char *contents)
{
	char *copy;
	char *saveptr;
	char *line;

	if (!contents) {
		return;
	}

	copy = duplicate_text(contents);
	if (!copy) {
		return;
	}

	snprintf(panel.right_label, sizeof(panel.right_label), "Backend: labwc");

	saveptr = NULL;
	for (line = strtok_r(copy, "\n", &saveptr);
		line;
		line = strtok_r(NULL, "\n", &saveptr)) {
		size_t len = strlen(line);
		while (len > 0 && line[len - 1] == '\r') {
			line[--len] = '\0';
		}
		if (len == 0 || line[0] == '#') {
			continue;
		}
		char *eq = strchr(line, '=');
		if (!eq) {
			continue;
		}
		*eq = '\0';
		const char *key = line;
		const char *val = eq + 1;

		if (strcmp(key, "NSCDE_BACKEND") == 0) {
			snprintf(panel.right_label, sizeof(panel.right_label),
				"Backend: %s", val);
		} else if (strcmp(key, "NSCDE_THEME_NAME") == 0) {
			char theme_info[MAX_NAME_LEN];
			snprintf(theme_info, sizeof(theme_info),
				"  Theme: %s", val);
			strncat(panel.right_label, theme_info,
				sizeof(panel.right_label) - strlen(panel.right_label) - 1);
		} else if (strcmp(key, "NSCDE_CURRENT_WORKSPACE") == 0) {
			strncpy(panel.current_workspace, val,
				sizeof(panel.current_workspace) - 1);
		} else if (strcmp(key, "NSCDE_WORKSPACES") == 0) {
			/* Parse comma-separated workspace names */
			panel.workspace_count = 0;
			char tmp[STATE_LINE_LEN];
			strncpy(tmp, val, sizeof(tmp) - 1);
			tmp[sizeof(tmp) - 1] = '\0';
			char *tok = strtok(tmp, ",");
			while (tok && panel.workspace_count < MAX_WORKSPACES) {
				/* Trim leading spaces */
				while (*tok == ' ') tok++;
				strncpy(panel.workspaces[panel.workspace_count].name,
					tok, MAX_NAME_LEN - 1);
				panel.workspaces[panel.workspace_count].active = false;
				panel.workspace_count++;
				tok = strtok(NULL, ",");
			}
		} else if (strncmp(key, "NSCDE_PALETTE_", 14) == 0) {
			int idx = atoi(key + 14);
			double color[4];
			if (idx >= 1 && idx <= 8 && parse_hex_color(val, color)) {
				memcpy(panel.palette_slots.color[idx - 1], color, sizeof(color));
			}
		} else if (strcmp(key, "NSCDE_FP_VARIANT") == 0) {
			int variant = atoi(val);
			if (variant == 5 || variant == 8) {
				panel.fp_variant = variant;
			}
		}
	}
	free(copy);
	recalculate_panel_palettes();
	panel.dirty = true;
	request_render();
}

static void
parse_env_file(void)
{
	char *contents = read_text_file(panel.panel_env_path);

	if (!contents) {
		return;
	}

	parse_env_contents(contents);
	free(contents);
}

static void
parse_workspaces_env_contents(const char *contents)
{
	char *copy;
	char *saveptr;
	char *line;

	if (!contents) {
		return;
	}

	copy = duplicate_text(contents);
	if (!copy) {
		return;
	}

	saveptr = NULL;
	for (line = strtok_r(copy, "\n", &saveptr);
		line;
		line = strtok_r(NULL, "\n", &saveptr)) {
		size_t len = strlen(line);
		while (len > 0 && line[len - 1] == '\r') {
			line[--len] = '\0';
		}
		if (len == 0 || line[0] == '#') {
			continue;
		}
		char *eq = strchr(line, '=');
		if (!eq) {
			continue;
		}
		*eq = '\0';
		const char *key = line;
		const char *val = eq + 1;

		if (strcmp(key, "NSCDE_CURRENT_WORKSPACE") == 0) {
			strncpy(panel.current_workspace, val,
				sizeof(panel.current_workspace) - 1);
			panel.current_workspace[sizeof(panel.current_workspace) - 1] = '\0';
		} else if (strcmp(key, "NSCDE_PAGER_COMMAND_FIFO") == 0) {
			strncpy(panel.pager_fifo_path, val,
				sizeof(panel.pager_fifo_path) - 1);
			panel.pager_fifo_path[sizeof(panel.pager_fifo_path) - 1] = '\0';
		} else if (strcmp(key, "NSCDE_WORKSPACES") == 0) {
			panel.workspace_count = 0;
			char tmp[STATE_LINE_LEN];
			strncpy(tmp, val, sizeof(tmp) - 1);
			tmp[sizeof(tmp) - 1] = '\0';
			char *tok = strtok(tmp, ",");
			while (tok && panel.workspace_count < MAX_WORKSPACES) {
				while (*tok == ' ') tok++;
				strncpy(panel.workspaces[panel.workspace_count].name,
					tok, MAX_NAME_LEN - 1);
				panel.workspaces[panel.workspace_count].name[MAX_NAME_LEN - 1] = '\0';
				panel.workspaces[panel.workspace_count].active = false;
				panel.workspace_count++;
				tok = strtok(NULL, ",");
			}
		}
	}
	free(copy);
	panel.dirty = true;
	request_render();
}

static void
parse_workspaces_env_file(void)
{
	char *contents = read_text_file(panel.workspaces_env_path);

	if (!contents) {
		return;
	}

	parse_workspaces_env_contents(contents);
	free(contents);
}

/* ---- Subpanel env file parsing ---- */

static void
parse_subpanel_env_contents(const char *contents)
{
	char *copy;
	char *saveptr;
	char *line;

	if (!contents) {
		return;
	}

	copy = duplicate_text(contents);
	if (!copy) {
		return;
	}

	/* Clear existing subpanel data */
	for (int i = 0; i < MAX_SUBPANELS; i++) {
		panel.subpanels[i].entry_count = 0;
		panel.subpanels[i].enabled = false;
		panel.subpanels[i].name[0] = '\0';
		panel.subpanels[i].width = 160;
	}
	panel.subpanel_count = 0;

	int max_enabled = 0;

	saveptr = NULL;
	for (line = strtok_r(copy, "\n", &saveptr);
		line;
		line = strtok_r(NULL, "\n", &saveptr)) {
		size_t len = strlen(line);
		while (len > 0 && line[len - 1] == '\r') {
			line[--len] = '\0';
		}
		if (len == 0 || line[0] == '#') {
			continue;
		}
		char *eq = strchr(line, '=');
		if (!eq) {
			continue;
		}
		*eq = '\0';
		const char *key = line;
		const char *val = eq + 1;

		/* NSCDE_SUBPANEL_<N>_NAME */
		if (strncmp(key, "NSCDE_SUBPANEL_", 15) == 0) {
			const char *p = key + 15;

			/* Skip "COUNT" key */
			if (strcmp(p, "COUNT") == 0) {
				continue;
			}

			/* Parse subpanel index */
			int sp_idx = atoi(p) - 1;  /* 1-based to 0-based */
			if (sp_idx < 0 || sp_idx >= MAX_SUBPANELS) {
				continue;
			}

			/* Find the underscore after the index */
			const char *rest = p;
			while (*rest && *rest != '_') rest++;
			if (*rest != '_') continue;
			rest++; /* skip underscore */

			struct subpanel_def *sp = &panel.subpanels[sp_idx];

			if (strcmp(rest, "NAME") == 0) {
				strncpy(sp->name, val, MAX_NAME_LEN - 1);
				sp->name[MAX_NAME_LEN - 1] = '\0';
			} else if (strcmp(rest, "WIDTH") == 0) {
				int v = atoi(val);
				if (v > 0 && v < 1024) {
					sp->width = v;
				}
			} else if (strcmp(rest, "ENABLED") == 0) {
				sp->enabled = (atoi(val) == 1);
			} else if (strcmp(rest, "ENTRY_COUNT") == 0) {
				sp->entry_count = atoi(val);
				if (sp->entry_count > MAX_SUBPANEL_ENTRIES) {
					sp->entry_count = MAX_SUBPANEL_ENTRIES;
				}
			} else if (strncmp(rest, "ENTRY_", 6) == 0) {
				/* NSCDE_SUBPANEL_<N>_ENTRY_<M>_TITLE/ICON/COMMAND */
				const char *ep = rest + 6;
				int entry_idx = atoi(ep) - 1;  /* 1-based to 0-based */
				if (entry_idx < 0 || entry_idx >= MAX_SUBPANEL_ENTRIES) {
					continue;
				}

				const char *field = ep;
				while (*field && *field != '_') field++;
				if (*field != '_') continue;
				field++; /* skip underscore */

				struct subpanel_entry *se = &sp->entries[entry_idx];
				if (strcmp(field, "TITLE") == 0) {
					strncpy(se->title, val, MAX_NAME_LEN - 1);
					se->title[MAX_NAME_LEN - 1] = '\0';
				} else if (strcmp(field, "TYPE") == 0) {
					strncpy(se->type, val, MAX_NAME_LEN - 1);
					se->type[MAX_NAME_LEN - 1] = '\0';
				} else if (strcmp(field, "ICON") == 0) {
					strncpy(se->icon, val, PATH_MAX_LEN - 1);
					se->icon[PATH_MAX_LEN - 1] = '\0';
				} else if (strcmp(field, "COMMAND") == 0) {
					strncpy(se->command, val, PATH_MAX_LEN - 1);
					se->command[PATH_MAX_LEN - 1] = '\0';
				}
			}

			if (sp->enabled && sp->entry_count > 0 && sp_idx >= max_enabled) {
				max_enabled = sp_idx + 1;
			}
		}
	}
	free(copy);

	panel.subpanel_count = max_enabled;

	/* Map launcher buttons to subpanels.
	 * The subpanel mapping follows NsCDE convention:
	 * launcher 0 (menu) has no subpanel, launchers 1..N map to S1..SN */
	for (int i = 0; i < panel.launcher_count; i++) {
		panel.launchers[i].subpanel_idx = -1;
	}
	for (int i = 1; i < panel.launcher_count && (i - 1) < panel.subpanel_count; i++) {
		int sp_idx = i - 1;
		if (panel.subpanels[sp_idx].enabled &&
			panel.subpanels[sp_idx].entry_count > 0) {
			panel.launchers[i].subpanel_idx = sp_idx;
		}
	}

	panel.dirty = true;
	request_render();
}

static void
parse_subpanel_env_file(void)
{
	char *contents = read_text_file(panel.subpanel_env_path);

	if (!contents) {
		return;
	}

	parse_subpanel_env_contents(contents);
	free(contents);
}

static void
recompute_panel_dimensions(void)
{
	panel.height = panel.layout_margin * 2
		+ panel.layout_border_width * 2
		+ panel.layout_height;
	panel.width = panel.layout_margin * 2
		+ panel.layout_border_width * 2
		+ panel.layout_left_handle_width
		+ panel.layout_left_bank_width
		+ panel.layout_center_section_width
		+ panel.layout_right_bank_width
		+ panel.layout_right_handle_width;

	if (panel.layer_surface) {
		zwlr_layer_surface_v1_set_size(panel.layer_surface,
			panel.width, panel.height);
		wl_surface_commit(panel.surface);
	}
}

static void
parse_layout_env_contents(const char *contents)
{
	if (!nscde_panel_layout_contract_parse_contents(contents,
		&panel.layout)) {
		return;
	}
	rebuild_launchers();
	rebuild_applets();
	recompute_panel_dimensions();
	panel.dirty = true;
	request_render();
}

static void
parse_layout_env_file(void)
{
	char *contents = read_text_file(panel.panel_layout_env_path);

	if (!contents) {
		return;
	}

	parse_layout_env_contents(contents);
	free(contents);
}

static void
parse_all_state_files(void)
{
	parse_layout_env_file();
	parse_env_file();
	parse_workspaces_env_file();
	parse_subpanel_env_file();
}

static bool
query_runtime_topic_and_parse(const char *topic, state_contents_parser_fn parser)
{
	char *contents = NULL;

	if (!topic || !parser) {
		return false;
	}
	if (!nscde_runtime_query_topic(topic, &contents)) {
		return false;
	}

	parser(contents);
	free(contents);
	return true;
}

static void
sync_state_from_best_source(void)
{
	if (!query_runtime_topic_and_parse("panel-layout",
		parse_layout_env_contents)) {
		parse_layout_env_file();
	}
	if (!query_runtime_topic_and_parse("panel", parse_env_contents)) {
		parse_env_file();
	}
	if (!query_runtime_topic_and_parse("workspaces",
		parse_workspaces_env_contents)) {
		parse_workspaces_env_file();
	}
	if (!query_runtime_topic_and_parse("subpanels",
		parse_subpanel_env_contents)) {
		parse_subpanel_env_file();
	}
}

static bool
setup_runtime_subscription(void)
{
	if (panel.runtime_active) {
		return true;
	}
	if (!nscde_runtime_subscribe_topics(
		"panel-layout,panel,workspaces,subpanels",
		&panel.runtime_subscription)) {
		return false;
	}

	pollfds[FD_RUNTIME].fd = panel.runtime_subscription.fd;
	pollfds[FD_RUNTIME].events = POLLIN;
	panel.runtime_active = true;
	return true;
}

static void
teardown_runtime_subscription(void)
{
	nscde_runtime_subscription_close(&panel.runtime_subscription);
	pollfds[FD_RUNTIME].fd = -1;
	pollfds[FD_RUNTIME].events = 0;
	panel.runtime_active = false;
}

static void
apply_runtime_frame(const struct nscde_runtime_frame *frame)
{
	if (!frame || frame->type != NSCDE_RUNTIME_FRAME_STATE ||
		!frame->contents) {
		return;
	}

	if (strcmp(frame->topic, "panel-layout") == 0) {
		parse_layout_env_contents(frame->contents);
	} else if (strcmp(frame->topic, "panel") == 0) {
		parse_env_contents(frame->contents);
	} else if (strcmp(frame->topic, "workspaces") == 0) {
		parse_workspaces_env_contents(frame->contents);
	} else if (strcmp(frame->topic, "subpanels") == 0) {
		parse_subpanel_env_contents(frame->contents);
	}
}

static void
handle_runtime_subscription(void)
{
	for (;;) {
		struct nscde_runtime_frame frame = {0};
		enum nscde_runtime_read_result result =
			nscde_runtime_subscription_read(&panel.runtime_subscription,
				&frame);

		if (result == NSCDE_RUNTIME_READ_FRAME) {
			if (frame.type == NSCDE_RUNTIME_FRAME_ERROR) {
				if (frame.message[0]) {
					fprintf(stderr,
						"nscde_paneld: runtime subscribe error: %s\n",
						frame.message);
				}
				nscde_runtime_frame_destroy(&frame);
				teardown_runtime_subscription();
				parse_all_state_files();
				break;
			}
			apply_runtime_frame(&frame);
			nscde_runtime_frame_destroy(&frame);
			continue;
		}
		if (result == NSCDE_RUNTIME_READ_CLOSED ||
			result == NSCDE_RUNTIME_READ_ERROR) {
			teardown_runtime_subscription();
			parse_all_state_files();
		}
		break;
	}
}

static void
refresh_state_transport(void)
{
	if (panel.runtime_active) {
		return;
	}

	sync_state_from_best_source();
	if (setup_runtime_subscription()) {
		handle_runtime_subscription();
	}
}

/* ---- Launcher button management ---- */

static void
rebuild_launchers(void)
{
	panel.launcher_count = 0;

	/* Parse comma-separated module names */
	char tmp[MAX_NAME_LEN];
	strncpy(tmp, panel.layout_left_modules, sizeof(tmp) - 1);
	tmp[sizeof(tmp) - 1] = '\0';

	char *tok = strtok(tmp, ",");
	while (tok && panel.launcher_count < MAX_LAUNCHERS) {
		/* Trim leading spaces */
		while (*tok == ' ') tok++;

		struct launcher_button *lb =
			&panel.launchers[panel.launcher_count];
		strncpy(lb->module, tok, sizeof(lb->module) - 1);
		lb->module[sizeof(lb->module) - 1] = '\0';
		lb->x = 0;
		lb->width = panel.layout_launcher_unit_width;
		lb->icon_size = panel.layout_launcher_icon_size;
		lb->subpanel_idx = -1;

		if (!lookup_panel_module(tok,
			lb->label, sizeof(lb->label),
			lb->command, sizeof(lb->command),
			&lb->content_type, &lb->show_label)) {
			/* Unknown module: use capitalized name as label,
			 * no command */
			strncpy(lb->label, tok, sizeof(lb->label) - 1);
			lb->label[sizeof(lb->label) - 1] = '\0';
			/* Capitalize first letter */
			if (lb->label[0] >= 'a' && lb->label[0] <= 'z') {
				lb->label[0] -= 32;
			}
			lb->command[0] = '\0';
			lb->content_type = APPLET_UNKNOWN;
			lb->show_label = false;
		}

		panel.launcher_count++;
		tok = strtok(NULL, ",");
	}

	/* Compute left area width from launcher geometry:
	 * handle + launcher_count * unit_width
	 * This matches the original CDE layout:
	 *   21px handle + N * 63px units */
	if (panel.launcher_count > 0) {
		panel.layout_left_area_width = panel.layout_left_handle_width
			+ panel.launcher_count * panel.layout_launcher_unit_width;
	} else {
		panel.layout_left_area_width = panel.layout_left_handle_width;
	}

	/* Update section geometry to match launcher state */
	panel.layout_left_launcher_count = panel.launcher_count;
	panel.layout_left_bank_width = panel.launcher_count
		* panel.layout_launcher_unit_width;
	if (panel.launcher_count == 0) {
		panel.layout_left_bank_width = 0;
	}
	panel.layout_center_section_x = panel.layout_left_handle_width
		+ panel.layout_left_bank_width;
}

/* ---- Applet slot management ---- */

static enum applet_type
applet_type_from_name(const char *name)
{
	if (strcmp(name, "clock") == 0) return APPLET_CLOCK;
	if (strcmp(name, "date") == 0) return APPLET_DATE;
	if (strcmp(name, "mail") == 0) return APPLET_MAIL;
	if (strcmp(name, "load") == 0) return APPLET_LOAD;
	return APPLET_UNKNOWN;
}

static bool
lookup_panel_module(const char *name, char *label, size_t label_size,
	char *command, size_t command_size, enum applet_type *content_type,
	bool *show_label)
{
	static const struct {
		const char *name;
		const char *label;
		const char *command;
		enum applet_type content_type;
		bool show_label;
	} module_map[] = {
		{ "clock", "Clock", "", APPLET_CLOCK, false },
		{ "date", "Date", "nscde_calendar", APPLET_DATE, false },
		{ "mail", "Mail", "xdg-email", APPLET_MAIL, false },
		{ "load", "Load", "", APPLET_LOAD, false },
		{ "style", "Style", "nscde_stylemgr", APPLET_UNKNOWN, false },
		{ "home", "Home", "xdg-open $HOME", APPLET_UNKNOWN, false },
		{ "term", "Term", "weston-terminal", APPLET_UNKNOWN, false },
		{ "apps", "Apps", "nscde_appfinder", APPLET_UNKNOWN, false },
		{ "help", "Help", "xdg-open ${NSCDE_ROOT:-/opt/NsCDE}/share/doc/NsCDE/html/index.html", APPLET_UNKNOWN, false },
		{ "print", "Print", "xdg-open", APPLET_UNKNOWN, false },
		{ "multimedia", "Media", "xdg-open", APPLET_UNKNOWN, false },
		{ "lock", "Lock", "xscreensaver-command -lock", APPLET_UNKNOWN, false },
		{ "exit", "Exit", "nscde_session_command quit", APPLET_UNKNOWN, false },
		{ NULL, NULL, NULL, APPLET_UNKNOWN, false }
	};

	for (int i = 0; module_map[i].name; i++) {
		if (strcmp(name, module_map[i].name) == 0) {
			strncpy(label, module_map[i].label, label_size - 1);
			label[label_size - 1] = '\0';
			strncpy(command, module_map[i].command, command_size - 1);
			command[command_size - 1] = '\0';
			*content_type = module_map[i].content_type;
			*show_label = module_map[i].show_label;
			return true;
		}
	}

	return false;
}

static void
rebuild_applets(void)
{
	panel.applet_count = 0;

	char tmp[MAX_NAME_LEN];
	strncpy(tmp, panel.layout_right_modules, sizeof(tmp) - 1);
	tmp[sizeof(tmp) - 1] = '\0';

	char *tok = strtok(tmp, ",");
	while (tok && panel.applet_count < MAX_APPLETS) {
		while (*tok == ' ') tok++;

		struct applet_slot *as = &panel.applets[panel.applet_count];
		as->is_launcher = false;
		as->subpanel_idx = -1;
		as->type = applet_type_from_name(tok);
		strncpy(as->name, tok, sizeof(as->name) - 1);
		as->name[sizeof(as->name) - 1] = '\0';
		if (as->type == APPLET_UNKNOWN) {
			enum applet_type module_type;
			bool show_label;
			if (lookup_panel_module(tok,
				as->label, sizeof(as->label),
				as->command, sizeof(as->command),
				&module_type, &show_label)) {
				as->is_launcher = (module_type == APPLET_UNKNOWN);
				as->type = module_type;
			} else {
				strncpy(as->label, tok, sizeof(as->label) - 1);
				as->label[sizeof(as->label) - 1] = '\0';
				as->command[0] = '\0';
				as->is_launcher = true;
			}
		}
		if (as->is_launcher) {
			as->subpanel_idx = right_launcher_subpanel_index(panel.applet_count);
		}

		switch (as->type) {
		case APPLET_CLOCK:
			as->width = panel.layout_applet_clock_size;
			as->height = panel.layout_applet_clock_size;
			break;
		case APPLET_DATE:
			as->width = panel.layout_applet_date_size;
			as->height = panel.layout_applet_date_size;
			break;
		case APPLET_MAIL:
			as->width = panel.layout_applet_mail_size;
			as->height = panel.layout_applet_mail_size;
			break;
		case APPLET_LOAD:
			as->width = panel.layout_applet_load_width;
			as->height = panel.layout_applet_load_height;
			break;
		default:
			as->width = panel.layout_launcher_unit_width;
			as->height = panel.layout_body_height;
			break;
		}
		if (!as->is_launcher && as->command[0] == '\0') {
			enum applet_type module_type;
			bool show_label;
			lookup_panel_module(tok,
				as->label, sizeof(as->label),
				as->command, sizeof(as->command),
				&module_type, &show_label);
		}

		panel.applet_count++;
		tok = strtok(NULL, ",");
	}

	/* Compute right bank width from actual applet footprints */
	int right_bank = 0;
	for (int i = 0; i < panel.applet_count; i++) {
		right_bank += panel.applets[i].width;
		if (i > 0 && !panel.applets[i].is_launcher) {
			right_bank += panel.layout_applet_gap;
		}
	}
	panel.layout_right_bank_width = right_bank;
	panel.layout_right_launcher_count = panel.applet_count;
}

static int
right_launcher_subpanel_index(int launcher_idx)
{
	if (launcher_idx >= 0 && launcher_idx < 5) {
		return launcher_idx + 5;
	}
	if (launcher_idx >= 5 && launcher_idx < 10) {
		return launcher_idx + 10;
	}
	return -1;
}

/* ---- Applet state refresh ---- */

static void
refresh_applet_state(void)
{
	time_t now = time(NULL);
	struct tm *t = localtime(&now);
	if (t) {
		panel.applet_live.clock_hour = t->tm_hour;
		panel.applet_live.clock_minute = t->tm_min;
		panel.applet_live.clock_second = t->tm_sec;
		strftime(panel.applet_live.date_month,
			sizeof(panel.applet_live.date_month), "%b", t);
		strftime(panel.applet_live.date_day,
			sizeof(panel.applet_live.date_day), "%e", t);
	}

	double la[3];
	if (getloadavg(la, 3) == 3) {
		panel.applet_live.load_1min = la[0];
		int pct = (int)(la[0] * 100.0);
		if (pct < 0) pct = 0;
		if (pct > 100) pct = 100;
		panel.applet_live.load_bar_pct = pct;
	}
}

/* ---- Cairo helpers ---- */

static void
cairo_set_source_rgba_array(cairo_t *cr, const double color[4])
{
	cairo_set_source_rgba(cr, color[0], color[1], color[2], color[3]);
}

static PangoFontDescription *
make_pixel_font_description(const char *spec)
{
	PangoFontDescription *desc = pango_font_description_from_string(spec);
	const char *last_space;
	char *endptr = NULL;
	long size = 0;

	if (!desc || !spec) {
		return desc;
	}

	last_space = strrchr(spec, ' ');
	if (last_space && last_space[1] != '\0') {
		size = strtol(last_space + 1, &endptr, 10);
		if (endptr && *endptr == '\0' && size > 0) {
			pango_font_description_set_absolute_size(desc,
				scale_metric((int)size) * PANGO_SCALE);
		}
	}

	return desc;
}

static int
scale_metric(int value)
{
	int scale_pct = panel.layout_scale > 0 ? panel.layout_scale : 100;

	return (value * scale_pct + 50) / 100;
}

static PangoFontDescription *
make_scaled_font_description(const char *spec)
{
	PangoFontDescription *desc = pango_font_description_from_string(spec);
	const char *last_space;
	char family[MAX_NAME_LEN];
	char *endptr = NULL;
	long size = 0;
	int scaled_size;
	size_t family_len;

	if (!desc || !spec) {
		return desc;
	}

	last_space = strrchr(spec, ' ');
	if (!last_space || last_space[1] == '\0') {
		return desc;
	}

	size = strtol(last_space + 1, &endptr, 10);
	if (!(endptr && *endptr == '\0' && size > 0)) {
		return desc;
	}

	family_len = (size_t)(last_space - spec);
	if (family_len >= sizeof(family)) {
		family_len = sizeof(family) - 1;
	}
	memcpy(family, spec, family_len);
	family[family_len] = '\0';

	scaled_size = scale_metric((int)size);
	if (scaled_size < 1) {
		scaled_size = 1;
	}

	pango_font_description_free(desc);
	desc = pango_font_description_from_string(family);
	if (!desc) {
		return NULL;
	}
	pango_font_description_set_absolute_size(desc,
		scaled_size * PANGO_SCALE);

	return desc;
}

static void
draw_bevel_rect(cairo_t *cr, int x, int y, int w, int h,
	const double highlight[4], const double shadow[4], int bw)
{
	/* Top edge */
	cairo_set_source_rgba_array(cr, highlight);
	cairo_rectangle(cr, x, y, w, bw);
	cairo_fill(cr);
	/* Left edge */
	cairo_rectangle(cr, x, y, bw, h);
	cairo_fill(cr);
	/* Bottom edge */
	cairo_set_source_rgba_array(cr, shadow);
	cairo_rectangle(cr, x, y + h - bw, w, bw);
	cairo_fill(cr);
	/* Right edge */
	cairo_rectangle(cr, x + w - bw, y, bw, h);
	cairo_fill(cr);
}

struct panel_button_style {
	double bg[4];
	double hi[4];
	double sh[4];
	double fg[4];
	double fgsh[4];
	bool sunken;
};

enum frontpanel_button_variant {
	FP_BUTTON_NORMAL,
	FP_BUTTON_ACCENT,
	FP_BUTTON_SUNKEN,
};

static void
copy_rgba(double dst[4], const double src[4])
{
	memcpy(dst, src, sizeof(double) * 4);
}

static void
mix_rgba(double out[4], const double a[4], const double b[4], double t)
{
	for (int i = 0; i < 4; i++) {
		out[i] = a[i] * (1.0 - t) + b[i] * t;
	}
}

static void
frontpanel_button_style(struct panel_button_style *style,
	const struct cde_palette *button_pal, enum frontpanel_button_variant variant)
{
	static const double fp_text[4] = {
		1.0, 1.0, 1.0, 1.0,
	};

	copy_rgba(style->bg, button_pal->bg);
	copy_rgba(style->hi, button_pal->hi);
	copy_rgba(style->sh, button_pal->sh);
	copy_rgba(style->fg, fp_text);
	copy_rgba(style->fgsh, button_pal->sel);

	switch (variant) {
	case FP_BUTTON_SUNKEN:
		copy_rgba(style->hi, button_pal->sh);
		copy_rgba(style->sh, button_pal->hi);
		style->sunken = true;
		break;
	case FP_BUTTON_ACCENT:
	case FP_BUTTON_NORMAL:
	default:
		style->sunken = false;
		break;
	}
}

static void
workspace_button_style(struct panel_button_style *style,
	const struct cde_palette *pal, int index, bool active)
{
	static const double family_bg[4][4] = {
		{ 137.0 / 255.0, 152.0 / 255.0, 170.0 / 255.0, 1.0 },
		{ 198.0 / 255.0, 178.0 / 255.0, 168.0 / 255.0, 1.0 },
		{ 73.0 / 255.0, 146.0 / 255.0, 167.0 / 255.0, 1.0 },
		{ 183.0 / 255.0, 135.0 / 255.0, 141.0 / 255.0, 1.0 },
	};
	static const double family_hi[4][4] = {
		{ 204.0 / 255.0, 210.0 / 255.0, 218.0 / 255.0, 1.0 },
		{ 231.0 / 255.0, 222.0 / 255.0, 218.0 / 255.0, 1.0 },
		{ 173.0 / 255.0, 206.0 / 255.0, 215.0 / 255.0, 1.0 },
		{ 223.0 / 255.0, 202.0 / 255.0, 205.0 / 255.0, 1.0 },
	};
	static const double family_sh[4][4] = {
		{ 71.0 / 255.0, 78.0 / 255.0, 88.0 / 255.0, 1.0 },
		{ 107.0 / 255.0, 96.0 / 255.0, 91.0 / 255.0, 1.0 },
		{ 36.0 / 255.0, 73.0 / 255.0, 83.0 / 255.0, 1.0 },
		{ 94.0 / 255.0, 70.0 / 255.0, 73.0 / 255.0, 1.0 },
	};
	static const double fg_white[4] = {
		1.0, 1.0, 1.0, 1.0,
	};
	static const double fg_shadow[4] = {
		51.0 / 255.0, 51.0 / 255.0, 51.0 / 255.0, 1.0,
	};
	int family = index % 4;

	(void)pal;
	copy_rgba(style->bg, family_bg[family]);
	copy_rgba(style->fg, fg_white);
	copy_rgba(style->fgsh, fg_shadow);
	copy_rgba(style->hi, active ? family_sh[family] : family_hi[family]);
	copy_rgba(style->sh, active ? family_hi[family] : family_sh[family]);
	style->sunken = active;
}

static void
draw_panel_decorated_button(cairo_t *cr, const struct section_rect *r,
	const struct panel_button_style *style, int bw,
	const struct cde_palette *pal)
{
	struct section_rect slot = {
		.x = r->x - 1,
		.y = r->y - 1,
		.w = r->w + 2,
		.h = r->h + 2,
	};
	struct section_rect inner = {
		.x = r->x + 1,
		.y = r->y + 1,
		.w = r->w - 2,
		.h = r->h - 2,
	};
	if (inner.w < 1) {
		inner.w = 1;
	}
	if (inner.h < 1) {
		inner.h = 1;
	}

	if (style->sunken) {
		draw_bevel_rect(cr, slot.x, slot.y, slot.w, slot.h,
			pal->sh, pal->hi, 1);
		cairo_set_source_rgba_array(cr, style->bg);
		cairo_rectangle(cr, inner.x, inner.y, inner.w, inner.h);
		cairo_fill(cr);
		draw_bevel_rect(cr, inner.x, inner.y, inner.w, inner.h,
			style->hi, style->sh, bw);
		return;
	}

	draw_bevel_rect(cr, slot.x, slot.y, slot.w, slot.h,
		pal->sh, pal->hi, 1);
	cairo_set_source_rgba_array(cr, style->bg);
	cairo_rectangle(cr, inner.x, inner.y, inner.w, inner.h);
	cairo_fill(cr);
	draw_bevel_rect(cr, inner.x, inner.y, inner.w, inner.h,
		style->hi, style->sh, bw);
}

/* ---- Applet rendering ---- */

#define M_PI 3.14159265358979323846

static void
render_applet_clock(cairo_t *cr, int cx, int cy, int size,
	const struct cde_palette *pal)
{
	int radius = size / 2 - 2;
	int bw = 1;

	/* Clock face: raised circle on background */
	cairo_set_source_rgba_array(cr, pal->bg);
	cairo_arc(cr, cx, cy, radius, 0, 2 * M_PI);
	cairo_fill(cr);

	/* Raised bevel ring */
	cairo_set_source_rgba_array(cr, pal->hi);
	cairo_set_line_width(cr, bw);
	cairo_arc(cr, cx, cy, radius, 0, 2 * M_PI);
	cairo_stroke(cr);
	cairo_set_source_rgba_array(cr, pal->sh);
	cairo_arc(cr, cx, cy, radius - bw, 0, 2 * M_PI);
	cairo_stroke(cr);

	/* Hour marks */
	cairo_set_source_rgba_array(cr, pal->fg);
	for (int i = 0; i < 12; i++) {
		double angle = i * M_PI / 6.0;
		int inner = radius - 5;
		int outer = radius - 2;
		cairo_move_to(cr,
			cx + inner * sin(angle),
			cy - inner * cos(angle));
		cairo_line_to(cr,
			cx + outer * sin(angle),
			cy - outer * cos(angle));
		cairo_set_line_width(cr, (i % 3 == 0) ? 2.0 : 1.0);
		cairo_stroke(cr);
	}

	/* Hour hand */
	double h_angle = (panel.applet_live.clock_hour % 12
		+ panel.applet_live.clock_minute / 60.0) * M_PI / 6.0;
	int h_len = radius * 5 / 10;
	cairo_set_source_rgba_array(cr, pal->hi);
	cairo_set_line_width(cr, 3.0);
	cairo_move_to(cr, cx, cy);
	cairo_line_to(cr,
		cx + h_len * sin(h_angle),
		cy - h_len * cos(h_angle));
	cairo_stroke(cr);

	/* Minute hand */
	double m_angle = panel.applet_live.clock_minute * M_PI / 30.0;
	int m_len = radius * 7 / 10;
	cairo_set_source_rgba_array(cr, pal->sh);
	cairo_set_line_width(cr, 2.0);
	cairo_move_to(cr, cx, cy);
	cairo_line_to(cr,
		cx + m_len * sin(m_angle),
		cy - m_len * cos(m_angle));
	cairo_stroke(cr);

	/* Center dot */
	cairo_set_source_rgba_array(cr, pal->fg);
	cairo_arc(cr, cx, cy, 2, 0, 2 * M_PI);
	cairo_fill(cr);
}

static void
render_applet_date(cairo_t *cr, PangoLayout *layout, int x, int y,
	int w, int h, const struct cde_palette *pal)
{
	/* Raised bevel background */
	cairo_set_source_rgba_array(cr, pal->bg);
	cairo_rectangle(cr, x, y, w, h);
	cairo_fill(cr);
	draw_bevel_rect(cr, x, y, w, h, pal->hi, pal->sh, 1);

	/* Month text (top half) -- FVWM: pixelsize=12 */
	PangoFontDescription *date_font =
		make_scaled_font_description(panel.layout_applet_date_font);
	pango_layout_set_font_description(layout, date_font);

	cairo_set_source_rgba_array(cr, pal->fg);
	pango_layout_set_text(layout, panel.applet_live.date_month, -1);
	int tw, th;
	pango_layout_get_pixel_size(layout, &tw, &th);
	cairo_move_to(cr, x + (w - tw) / 2, y + (h / 2 - th - 1));
	pango_cairo_show_layout(cr, layout);

	/* Day number (bottom half) */
	pango_layout_set_text(layout, panel.applet_live.date_day, -1);
	pango_layout_get_pixel_size(layout, &tw, &th);
	cairo_move_to(cr, x + (w - tw) / 2, y + h / 2 + 1);
	pango_cairo_show_layout(cr, layout);

	pango_font_description_free(date_font);
}

static void
render_applet_mail(cairo_t *cr, int x, int y, int w, int h,
	const struct cde_palette *pal)
{
	/* Raised bevel background */
	cairo_set_source_rgba_array(cr, pal->bg);
	cairo_rectangle(cr, x, y, w, h);
	cairo_fill(cr);
	draw_bevel_rect(cr, x, y, w, h, pal->hi, pal->sh, 1);

	/* Envelope body */
	int env_x = x + w / 2 - 10;
	int env_y = y + h / 2 - 7;
	int env_w = 20;
	int env_h = 14;

	cairo_set_source_rgba_array(cr, pal->sbg);
	cairo_rectangle(cr, env_x, env_y, env_w, env_h);
	cairo_fill(cr);
	draw_bevel_rect(cr, env_x, env_y, env_w, env_h,
		pal->hi, pal->sh, 1);

	/* Envelope flap (V shape) */
	cairo_set_source_rgba_array(cr, pal->hi);
	cairo_set_line_width(cr, 1.0);
	cairo_move_to(cr, env_x, env_y);
	cairo_line_to(cr, env_x + env_w / 2, env_y + 5);
	cairo_line_to(cr, env_x + env_w, env_y);
	cairo_stroke(cr);

	/* New mail indicator: small colored bar at top */
	if (panel.applet_live.mail_has_new) {
		cairo_set_source_rgba(cr, 1.0, 0.2, 0.2, 1.0);
		cairo_rectangle(cr, env_x + 2, env_y - 3, env_w - 4, 2);
		cairo_fill(cr);
	}
}

static void
render_applet_load(cairo_t *cr, int x, int y, int w, int h,
	const struct cde_palette *pal)
{
	/* Raised bevel background */
	cairo_set_source_rgba_array(cr, pal->bg);
	cairo_rectangle(cr, x, y, w, h);
	cairo_fill(cr);
	draw_bevel_rect(cr, x, y, w, h, pal->hi, pal->sh, 1);

	/* Load bar: sunken area with fill level */
	int bar_x = x + 4;
	int bar_y = y + 6;
	int bar_w = w - 8;
	int bar_h = h - 12;

	/* Sunken recess */
	draw_bevel_rect(cr, bar_x, bar_y, bar_w, bar_h,
		pal->sh, pal->hi, 1);

	/* Fill from bottom */
	int fill_h = (bar_h - 2) * panel.applet_live.load_bar_pct / 100;
	if (fill_h > 0) {
		/* Color: green below 50%, yellow 50-80%, red above 80% */
		double r, g, b;
		if (panel.applet_live.load_bar_pct < 50) {
			r = 0.2; g = 0.7; b = 0.2;
		} else if (panel.applet_live.load_bar_pct < 80) {
			r = 0.8; g = 0.7; b = 0.1;
		} else {
			r = 0.8; g = 0.2; b = 0.1;
		}
		cairo_set_source_rgba(cr, r, g, b, 1.0);
		cairo_rectangle(cr, bar_x + 1,
			bar_y + bar_h - 1 - fill_h,
			bar_w - 2, fill_h);
		cairo_fill(cr);
	}
}

/* ---- Rendering ---- */

static void
draw_trigger_marker(cairo_t *cr, int cx, int cy, int size,
		const struct cde_palette *pal)
{
	double hi[4];
	double sh[4];
	double left_x;
	double right_x;
	double apex_x;
	double apex_y;
	double base_y;
	double inset;

	if (size < 4) {
		size = 4;
	}
	size = scale_metric(size);
	if (size < 4) {
		size = 4;
	}

	mix_rgba(hi, pal->bg, pal->hi, 0.78);
	mix_rgba(sh, pal->bg, pal->sh, 0.50);

	apex_x = cx + 0.5;
	apex_y = cy - (double)size * 0.75;
	base_y = cy + (double)size * 0.33;
	inset = size - 0.4;
	left_x = cx - inset + 0.5;
	right_x = cx + inset + 0.5;

	cairo_save(cr);
	cairo_set_antialias(cr, CAIRO_ANTIALIAS_GRAY);
	cairo_set_line_width(cr, scale_metric(1));
	cairo_set_line_join(cr, CAIRO_LINE_JOIN_MITER);
	cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT);

	cairo_set_source_rgba_array(cr, hi);
	cairo_move_to(cr, left_x, base_y);
	cairo_line_to(cr, apex_x, apex_y);
		cairo_line_to(cr, right_x - (double)size * 0.20, base_y);
	cairo_stroke(cr);

	cairo_set_source_rgba_array(cr, sh);
	cairo_move_to(cr, right_x, base_y);
		cairo_line_to(cr, apex_x, apex_y + 0.1);
		cairo_stroke(cr);
		cairo_move_to(cr, left_x + (double)size * 0.20, base_y);
		cairo_line_to(cr, right_x - (double)size * 0.05, base_y);
		cairo_stroke(cr);

	cairo_restore(cr);
}

static void
draw_trigger_band_background(cairo_t *cr, int x, int y, int w, int h,
	const struct cde_palette *pal)
{
	double band[4];

	mix_rgba(band, pal->bg, pal->hi, 0.18);
	cairo_set_source_rgba_array(cr, band);
	cairo_rectangle(cr, x, y, w, h);
	cairo_fill(cr);

	cairo_set_source_rgba_array(cr, pal->hi);
	cairo_rectangle(cr, x, y, w, 1);
	cairo_fill(cr);
	cairo_set_source_rgba_array(cr, pal->sh);
	cairo_rectangle(cr, x, y + h - 1, w, 1);
	cairo_fill(cr);
}

static void
fill_inner_section_slab(cairo_t *cr, int x, int y, int w, int h,
	const struct cde_palette *pal)
{
	double slab[4];

	mix_rgba(slab, pal->bg, pal->sh, 0.12);
	cairo_set_source_rgba_array(cr, slab);
	cairo_rectangle(cr, x, y, w, h);
	cairo_fill(cr);
}

static void
draw_handle_button_slot(cairo_t *cr, int x, int y, int w, int h,
	const struct cde_palette *pal)
{
	cairo_set_source_rgba_array(cr, pal->bg);
	cairo_rectangle(cr, x, y, w, h);
	cairo_fill(cr);
	draw_bevel_rect(cr, x, y, w, h, pal->hi, pal->sh, 1);
}

static void
draw_trigger_slot(cairo_t *cr, int x, int y, int w, int h,
	const struct cde_palette *pal)
{
	double slot[4];

	mix_rgba(slot, pal->bg, pal->hi, 0.10);
	cairo_set_source_rgba_array(cr, slot);
	cairo_rectangle(cr, x, y, w, h);
	cairo_fill(cr);
	draw_bevel_rect(cr, x, y, w, h, pal->hi, pal->sh, 1);
}

static void
draw_handle_reference_gaps(cairo_t *cr, const struct section_rect *handle,
	const struct section_rect *button, bool right_side)
{
	int sepw = panel.layout_section_separator_width;

	if (sepw < 1) {
		sepw = 1;
	}

	cairo_set_source_rgba_array(cr, panel.fp_gap_light);
	if (right_side) {
		cairo_rectangle(cr, handle->x, handle->y,
			handle->w, sepw);
		cairo_fill(cr);
		cairo_rectangle(cr, button->x,
			button->y + button->h,
			button->w, sepw);
		cairo_fill(cr);
		cairo_set_source_rgba_array(cr, panel.fp_gap_dark);
		cairo_rectangle(cr,
			handle->x + handle->w - sepw,
			handle->y + sepw,
			sepw,
			handle->h - sepw);
		cairo_fill(cr);
	} else {
		cairo_rectangle(cr, handle->x, handle->y,
			sepw, handle->h);
		cairo_fill(cr);
		cairo_rectangle(cr, button->x,
			handle->y,
			button->w, sepw);
		cairo_fill(cr);
		cairo_rectangle(cr, button->x,
			button->y + button->h,
			button->w, sepw);
		cairo_fill(cr);
	}
}


static void
draw_handle_button_glyph(cairo_t *cr, int x, int y, int w, int h,
		const struct cde_palette *pal, bool menu_button)
{
	int inset = scale_metric(4);
	int line_h = scale_metric(1);
	int line_gap = scale_metric(2);
	int square = scale_metric(4);

	if (inset < 1) {
		inset = 1;
	}
	if (line_h < 1) {
		line_h = 1;
	}
	if (line_gap < 1) {
		line_gap = 1;
	}
	if (square < 2) {
		square = 2;
	}

	cairo_set_source_rgba_array(cr, pal->sfg);
	if (menu_button) {
		int gy = y + (h - (3 * line_h + 2 * line_gap)) / 2;
		for (int i = 0; i < 3; i++) {
			cairo_rectangle(cr, x + inset,
				gy + i * (line_h + line_gap),
				w - inset * 2, line_h);
		}
		cairo_fill(cr);
	} else {
		cairo_rectangle(cr,
			x + (w - square) / 2,
			y + (h - square) / 2,
			square, square);
		cairo_fill(cr);
	}
}

static void
draw_handle_button(cairo_t *cr, int x, int y, int w, int h,
	const struct cde_palette *pal, bool menu_button)
{
	draw_handle_button_slot(cr, x, y, w, h, pal);
	draw_handle_button_glyph(cr, x, y, w, h, pal, menu_button);
}

static bool
render_asset_centered_native(cairo_t *cr, const char *relpath,
	const struct section_rect *slot)
{
	return nscde_pixel_icon_render_asset_centered(&panel.pixel_icons, cr,
		relpath, slot->x, slot->y, slot->w, slot->h, true);
}

static const char *
panel_module_icon_relpath(const char *module)
{
	static const struct {
		const char *module;
		const char *relpath;
	} icon_map[] = {
		{ "home", "icons/NsCDE/Fphome.l.pm" },
		{ "term", "icons/NsCDE/Fpterm.l.pm" },
		{ "print", "icons/NsCDE/Fpprnt.l.pm" },
		{ "style", "icons/NsCDE/Fpstyle.l.pm" },
		{ "apps", "icons/NsCDE/Fpapps.l.pm" },
		{ "multimedia", "icons/NsCDE/Multimedia.l.pm" },
		{ "help", "icons/NsCDE/Fphelp.l.pm" },
		{ NULL, NULL }
	};

	if (!module) {
		return NULL;
	}

	for (int i = 0; icon_map[i].module; i++) {
		if (strcmp(module, icon_map[i].module) == 0) {
			return icon_map[i].relpath;
		}
	}
	return NULL;
}

static void
draw_handle_grip(cairo_t *cr, int x, int y, int w, int h,
		const struct cde_palette *pal)
{
	int grip_w = scale_metric(7);
	int top_pad = scale_metric(4);
	int row_step = scale_metric(14);
	int left = x + (w - grip_w) / 2;

	if (grip_w < 3) {
		grip_w = 3;
	}
	if (row_step < 2) {
		row_step = 2;
	}

	for (int i = 0; i < 4; i++) {
		int gy = y + top_pad + i * row_step;
		cairo_set_source_rgba_array(cr, pal->hi);
		cairo_rectangle(cr, left, gy, grip_w, 1);
		cairo_fill(cr);
		cairo_set_source_rgba_array(cr, pal->sh);
		cairo_rectangle(cr, left, gy + 1, grip_w, 1);
		cairo_fill(cr);
	}
}

static void
draw_launcher_icon_placeholder(cairo_t *cr, const char *module,
	int x, int y, int w, int h, const struct cde_palette *pal)
{
	int ix = x + (w - 36) / 2;
	int iy = y + (h - 30) / 2;

	if (strcmp(module, "home") == 0) {
		cairo_set_source_rgba_array(cr, pal->fg);
		cairo_move_to(cr, ix + 18, iy);
		cairo_line_to(cr, ix + 34, iy + 12);
		cairo_line_to(cr, ix + 34, iy + 28);
		cairo_line_to(cr, ix + 2, iy + 28);
		cairo_line_to(cr, ix + 2, iy + 12);
		cairo_close_path(cr);
		cairo_stroke(cr);
		cairo_move_to(cr, ix + 6, iy + 13);
		cairo_line_to(cr, ix + 18, iy + 3);
		cairo_line_to(cr, ix + 30, iy + 13);
		cairo_stroke(cr);
	} else if (strcmp(module, "term") == 0) {
		cairo_rectangle(cr, ix + 2, iy + 3, 32, 22);
		cairo_stroke(cr);
		cairo_move_to(cr, ix + 8, iy + 11);
		cairo_line_to(cr, ix + 14, iy + 15);
		cairo_line_to(cr, ix + 8, iy + 19);
		cairo_stroke(cr);
		cairo_move_to(cr, ix + 17, iy + 19);
		cairo_line_to(cr, ix + 28, iy + 19);
		cairo_stroke(cr);
	} else if (strcmp(module, "print") == 0) {
		cairo_rectangle(cr, ix + 7, iy + 2, 22, 8);
		cairo_stroke(cr);
		cairo_rectangle(cr, ix + 4, iy + 10, 28, 10);
		cairo_stroke(cr);
		cairo_rectangle(cr, ix + 8, iy + 20, 20, 8);
		cairo_stroke(cr);
	} else if (strcmp(module, "style") == 0) {
		cairo_arc(cr, ix + 12, iy + 12, 5, 0, 2 * M_PI);
		cairo_stroke(cr);
		cairo_arc(cr, ix + 22, iy + 12, 5, 0, 2 * M_PI);
		cairo_stroke(cr);
		cairo_arc(cr, ix + 17, iy + 20, 5, 0, 2 * M_PI);
		cairo_stroke(cr);
		cairo_move_to(cr, ix + 25, iy + 25);
		cairo_line_to(cr, ix + 33, iy + 30);
		cairo_stroke(cr);
	} else if (strcmp(module, "apps") == 0) {
		cairo_rectangle(cr, ix + 5, iy + 2, 24, 28);
		cairo_stroke(cr);
		cairo_move_to(cr, ix + 10, iy + 10);
		cairo_line_to(cr, ix + 22, iy + 22);
		cairo_stroke(cr);
		cairo_move_to(cr, ix + 20, iy + 8);
		cairo_line_to(cr, ix + 26, iy + 2);
		cairo_stroke(cr);
	} else if (strcmp(module, "multimedia") == 0) {
		cairo_rectangle(cr, ix + 4, iy + 4, 12, 20);
		cairo_stroke(cr);
		cairo_move_to(cr, ix + 9, iy + 4);
		cairo_line_to(cr, ix + 18, iy + 10);
		cairo_line_to(cr, ix + 18, iy + 28);
		cairo_stroke(cr);
		cairo_arc(cr, ix + 24, iy + 23, 4, 0, 2 * M_PI);
		cairo_stroke(cr);
	} else if (strcmp(module, "help") == 0) {
		cairo_rectangle(cr, ix + 4, iy + 3, 24, 26);
		cairo_stroke(cr);
		cairo_move_to(cr, ix + 16, iy + 8);
		cairo_show_text(cr, "?");
	} else {
		cairo_rectangle(cr, ix + 4, iy + 4, 28, 24);
		cairo_stroke(cr);
	}
}

static void
render_module_in_launcher_body(cairo_t *cr, struct launcher_button *lb,
	PangoLayout *layout, const struct cde_palette *pal,
	int btn_x, int body_y, int body_h)
{
	int content_x = btn_x + (lb->width - lb->icon_size) / 2;
	int content_y = body_y + (body_h - lb->icon_size) / 2;

	switch (lb->content_type) {
	case APPLET_CLOCK:
		render_applet_clock(cr,
			btn_x + lb->width / 2,
			body_y + body_h / 2,
			lb->icon_size, pal);
		break;
	case APPLET_DATE:
		render_applet_date(cr, layout,
			btn_x + (lb->width - lb->icon_size) / 2,
			content_y,
			lb->icon_size, lb->icon_size, pal);
		break;
	case APPLET_MAIL:
		render_applet_mail(cr,
			btn_x + (lb->width - lb->icon_size) / 2,
			content_y,
			lb->icon_size, lb->icon_size, pal);
		break;
		case APPLET_LOAD:
			render_applet_load(cr,
				btn_x + (lb->width - panel.layout_applet_load_width) / 2,
				body_y + (body_h - panel.layout_applet_load_height) / 2,
				panel.layout_applet_load_width,
				panel.layout_applet_load_height, pal);
			break;
		default:
			if (!nscde_pixel_icon_render_asset_centered(&panel.pixel_icons, cr,
					panel_module_icon_relpath(lb->module),
					content_x, content_y,
					lb->icon_size, lb->icon_size, true)) {
				cairo_set_source_rgba_array(cr, pal->fg);
				draw_launcher_icon_placeholder(cr, lb->module,
					content_x, content_y,
				lb->icon_size, lb->icon_size, pal);
		}
		break;
	}
}

static void
render_section_left_handle(cairo_t *cr, const struct section_rect *r,
	const struct cde_palette *pal, int bw)
{
	cairo_set_source_rgba_array(cr, pal->bg);
	cairo_rectangle(cr, r->x, r->y, r->w, r->h);
	cairo_fill(cr);
	draw_bevel_rect(cr, r->x, r->y, r->w, r->h,
		pal->hi, pal->sh, bw);
	draw_handle_reference_gaps(cr, r,
		&panel.layout_model.left_handle_button, false);

	draw_handle_button_slot(cr,
		panel.layout_model.left_handle_button.x,
		panel.layout_model.left_handle_button.y,
		panel.layout_model.left_handle_button.w,
		panel.layout_model.left_handle_button.h,
		pal);
	if (!render_asset_centered_native(cr, "icons/NsCDE/FpMenu.xpm",
			&panel.layout_model.left_handle_button)) {
		draw_handle_button_glyph(cr,
			panel.layout_model.left_handle_button.x,
			panel.layout_model.left_handle_button.y,
			panel.layout_model.left_handle_button.w,
			panel.layout_model.left_handle_button.h,
			pal,
			true);
	}
	if (!nscde_pixel_icon_render_asset(&panel.pixel_icons, cr,
			"icons/NsCDE/FpHandle.xpm",
			panel.layout_model.left_handle_grip.x,
			panel.layout_model.left_handle_grip.y,
			panel.layout_model.left_handle_grip.w,
			panel.layout_model.left_handle_grip.h)) {
		draw_handle_grip(cr,
			panel.layout_model.left_handle.x,
			panel.layout_model.left_handle_grip.y,
			panel.layout_model.left_handle.w,
			panel.layout_model.left_handle_grip.h,
			pal);
	}
}

static void
render_section_left_bank(cairo_t *cr, const struct section_rect *r,
	PangoLayout *layout, PangoFontDescription *font_desc,
	const struct cde_palette *pal, int bw)
{
	int trigger_y = r->y - panel.layout_trigger_height;
	struct panel_button_style button_style;
	const struct cde_palette *button_pal = &panel.fp_button_palette;

	fill_inner_section_slab(cr, r->x, trigger_y,
		r->w, panel.layout_trigger_height + r->h, pal);
	draw_bevel_rect(cr, r->x, r->y, r->w, r->h,
		pal->hi, pal->sh, bw);
	cairo_set_source_rgba_array(cr, pal->sh);
	cairo_rectangle(cr, r->x, trigger_y + panel.layout_trigger_height + r->h - 1,
		r->w, 1);
	cairo_fill(cr);
	frontpanel_button_style(&button_style, button_pal, FP_BUTTON_NORMAL);

	for (int i = 0; i < panel.launcher_count; i++) {
		struct launcher_button *lb = &panel.launchers[i];
		int btn_w = lb->width;
		int btn_x = lb->x;
		int label_h = 0;
		int tw = 0;
		int th = 0;

		if (lb->label[0]) {
			pango_layout_set_font_description(layout, font_desc);
			pango_layout_set_text(layout, lb->label, -1);
			pango_layout_get_pixel_size(layout, &tw, &th);
			label_h = th;
		}

		draw_trigger_slot(cr, btn_x, lb->trigger_y, btn_w,
			lb->trigger_h, pal);
		draw_trigger_marker(cr,
			btn_x + btn_w / 2,
			lb->trigger_y + lb->trigger_h / 2,
			4,
			pal);

		struct section_rect body_rect = {
			.x = btn_x,
			.y = lb->body_y,
			.w = btn_w,
			.h = lb->body_h,
		};

		render_module_in_launcher_body(cr, lb, layout, button_pal,
			btn_x, lb->body_y, lb->body_h);

		if (lb->show_label && lb->label[0]) {
			int label_x = btn_x + (btn_w - tw) / 2;
			int label_y = r->y + r->h - label_h - 1;
			cairo_set_source_rgba_array(cr, button_style.fgsh);
			cairo_move_to(cr, label_x + 1, label_y + 1);
			pango_cairo_show_layout(cr, layout);
			cairo_set_source_rgba_array(cr, button_style.fg);
			cairo_move_to(cr, label_x, label_y);
			pango_cairo_show_layout(cr, layout);
		}
	}
}

static void
compute_panel_layout_model(struct panel_layout_model *model)
{
	int margin = panel.layout_margin;
	int border = panel.layout_border_width;
	int lh = panel.layout_left_handle_width;
	int rh = panel.layout_right_handle_width;
	int lbw = panel.layout_left_bank_width;
	int rbw = panel.layout_right_bank_width;
	int csw = panel.layout_center_section_width;
	int csx = panel.layout_center_section_x;
	int trigger_h = panel.layout_trigger_height;
	int body_h = panel.layout_body_height;
	int strip_h = panel.layout_bottom_strip_height;

	model->left_handle = (struct section_rect) {
		.x = margin + border,
		.y = margin + border,
		.w = lh,
		.h = panel.height - 2 * margin - 2 * border,
	};
	model->left_bank = (struct section_rect) {
		.x = margin + border + lh,
		.y = margin + border + trigger_h,
		.w = lbw,
		.h = body_h,
	};
	model->center = (struct section_rect) {
		.x = margin + border + csx,
		.y = margin + border,
		.w = csw,
		.h = panel.height - 2 * margin - 2 * border,
	};
		model->right_bank = (struct section_rect) {
			.x = panel.width - margin - border - rh - rbw,
			.y = margin + border + trigger_h,
			.w = rbw,
			.h = body_h,
		};
	model->right_handle = (struct section_rect) {
		.x = panel.width - margin - border - rh,
		.y = margin + border,
		.w = rh,
		.h = panel.height - 2 * margin - 2 * border,
	};
	model->bottom_strip = (struct section_rect) {
		.x = margin + border + lh,
		.y = margin + border + trigger_h + body_h,
		.w = model->right_bank.x - (margin + border + lh) + rbw,
		.h = strip_h,
	};

		model->left_handle_button = (struct section_rect) {
			.x = model->left_handle.x + scale_metric(1),
			.y = model->left_handle.y + scale_metric(1),
			.w = scale_metric(19),
			.h = scale_metric(14),
		};
		model->left_handle_grip = (struct section_rect) {
			.x = model->left_handle.x + scale_metric(1),
			.y = model->left_handle.y + scale_metric(16),
			.w = scale_metric(19),
			.h = scale_metric(63),
		};

		model->right_handle_button = (struct section_rect) {
			.x = model->right_handle.x,
			.y = model->right_handle.y + scale_metric(1),
			.w = scale_metric(20),
			.h = scale_metric(14),
		};
		model->right_handle_grip = (struct section_rect) {
			.x = model->right_handle.x,
			.y = model->right_handle.y + scale_metric(16),
			.w = scale_metric(20),
			.h = scale_metric(63),
		};

	int launcher_x = model->left_bank.x;
	for (int i = 0; i < panel.launcher_count; i++) {
		panel.launchers[i].x = launcher_x;
		panel.launchers[i].trigger_y = model->left_bank.y - panel.layout_trigger_height;
		panel.launchers[i].trigger_h = panel.layout_trigger_height;
		panel.launchers[i].body_y = model->left_bank.y;
		panel.launchers[i].body_h = model->left_bank.h;
		launcher_x += panel.launchers[i].width + panel.layout_launcher_gap;
	}

	int applet_x = model->right_bank.x + model->right_bank.w;
		for (int i = panel.applet_count - 1; i >= 0; i--) {
			struct applet_slot *as = &panel.applets[i];
			int slot_gap = as->is_launcher ? 0 : panel.layout_applet_gap;
			applet_x -= as->width;
			as->x = applet_x;
			as->trigger_y = model->right_bank.y - panel.layout_trigger_height;
			as->trigger_h = panel.layout_trigger_height;
			as->body_y = model->right_bank.y;
			as->body_h = model->right_bank.h;
			applet_x -= slot_gap;
		}

	int inner_pad = panel.layout_wsm_inner_pad;
	int side_w = panel.layout_wsm_side_width;
	int util_w = panel.layout_wsm_utility_width;
	int section_gap = panel.layout_wsm_section_gap;
	int scale_pct = panel.layout_scale > 0 ? panel.layout_scale : 100;
	int inner_x = model->center.x + inner_pad;
	int inner_y = model->center.y + inner_pad;
	int inner_w = model->center.w - 2 * inner_pad;
	int inner_h = model->center.h - 2 * inner_pad - panel.layout_bottom_strip_height;
	int grid_x = inner_x + side_w + section_gap;
	int grid_w = inner_w - side_w - util_w - 2 * section_gap;
	int util_x = grid_x + grid_w + section_gap;
	int grid_y = inner_y + panel.layout_wsm_grid_vpad;
	int grid_h = inner_h - 2 * panel.layout_wsm_grid_vpad;
	int row_h = inner_h / 2;
	int top_row_y = inner_y;
	int bottom_row_y = inner_y + inner_h - row_h;
	int rows = panel.workspace_count > 2 ? 2 : 1;
	int cols = rows == 1 ? (panel.workspace_count > 0 ? panel.workspace_count : 1) : 2;
	int btn_gap = panel.layout_button_gap;
	int btn_w;
	int btn_h;
	int lock_h = panel.layout_wsm_lock_height;
	int exit_h = panel.layout_wsm_exit_height;
	int load_w = util_w - panel.layout_wsm_load_inset_side * 2;
	int load_h = panel.layout_wsm_load_height;
	int lock_icon_w = (24 * scale_pct + 50) / 100;
	int lock_icon_h = (24 * scale_pct + 50) / 100;
	int pgm_icon_w = (22 * scale_pct + 50) / 100;
	int pgm_icon_h = (20 * scale_pct + 50) / 100;
	int exit_icon_w = (24 * scale_pct + 50) / 100;
	int exit_icon_h = (24 * scale_pct + 50) / 100;

	if (grid_w < 1) {
		grid_w = 1;
	}
	btn_w = (grid_w - (cols - 1) * btn_gap) / cols;
	btn_h = (grid_h - (rows - 1) * btn_gap) / rows;
	if (btn_w < panel.layout_button_min_width) {
		btn_w = panel.layout_button_min_width;
	}

	model->wsm_lock_slot = (struct section_rect) {
		.x = inner_x,
		.y = top_row_y + (row_h - lock_h) / 2,
		.w = side_w,
		.h = lock_h,
	};
	model->wsm_pgm_slot = (struct section_rect) {
		.x = inner_x,
		.y = bottom_row_y + (row_h - lock_h) / 2,
		.w = side_w,
		.h = lock_h,
	};
	model->wsm_grid = (struct section_rect) {
		.x = grid_x,
		.y = grid_y,
		.w = grid_w,
		.h = grid_h,
	};
	model->wsm_load_slot = (struct section_rect) {
		.x = util_x + panel.layout_wsm_load_inset_side,
		.y = top_row_y + panel.layout_wsm_load_inset_top,
		.w = load_w,
		.h = load_h,
	};
	model->wsm_exit_slot = (struct section_rect) {
		.x = util_x + panel.layout_wsm_utility_inset_side,
		.y = bottom_row_y + row_h - exit_h - panel.layout_wsm_exit_inset_bottom,
		.w = util_w - panel.layout_wsm_utility_inset_side * 2,
		.h = exit_h,
	};
	model->wsm_lock_icon = (struct section_rect) {
		.x = inner_x + (side_w - lock_icon_w) / 2,
		.y = top_row_y + (row_h - lock_icon_h) / 2,
		.w = lock_icon_w,
		.h = lock_icon_h,
	};
	model->wsm_pgm_icon = (struct section_rect) {
		.x = inner_x + (side_w - pgm_icon_w) / 2,
		.y = bottom_row_y + (row_h - pgm_icon_h) / 2,
		.w = pgm_icon_w,
		.h = pgm_icon_h,
	};
	model->wsm_exit_icon = (struct section_rect) {
		.x = util_x + (util_w - exit_icon_w) / 2,
		.y = bottom_row_y + (row_h - exit_icon_h) / 2,
		.w = exit_icon_w,
		.h = exit_icon_h,
	};

	for (int i = 0; i < panel.workspace_count; i++) {
		struct ws_button *btn = &panel.workspaces[i];
		int row = rows == 1 ? 0 : i / 2;
		int col = rows == 1 ? i : i % 2;
		btn->x = grid_x + col * (btn_w + btn_gap);
		btn->y = grid_y + row * (btn_h + btn_gap);
		btn->width = btn_w;
		btn->height = btn_h;
		btn->active = strcmp(btn->name, panel.current_workspace) == 0;
	}
}

static bool
point_in_rect(int x, int y, const struct section_rect *r)
{
	return x >= r->x && x < r->x + r->w &&
		y >= r->y && y < r->y + r->h;
}

static struct panel_hit_result
hit_test_panel(int x, int y)
{
	struct panel_hit_result hit = { PANEL_HIT_NONE, -1, -1 };

	compute_panel_layout_model(&panel.layout_model);

	if (point_in_rect(x, y, &panel.layout_model.left_handle_button)) {
		hit.role = PANEL_HIT_LEFT_MENU_BUTTON;
		return hit;
	}
	if (point_in_rect(x, y, &panel.layout_model.left_handle_grip)) {
		hit.role = PANEL_HIT_LEFT_HANDLE;
		return hit;
	}
	if (point_in_rect(x, y, &panel.layout_model.right_handle_button)) {
		hit.role = PANEL_HIT_RIGHT_ICONIFY_BUTTON;
		return hit;
	}
	if (point_in_rect(x, y, &panel.layout_model.right_handle_grip)) {
		hit.role = PANEL_HIT_RIGHT_HANDLE;
		return hit;
	}

	if (point_in_rect(x, y, &panel.layout_model.wsm_lock_slot)) {
		hit.role = PANEL_HIT_WSM_LOCK;
		return hit;
	}
	if (point_in_rect(x, y, &panel.layout_model.wsm_pgm_slot)) {
		hit.role = PANEL_HIT_WSM_PGM;
		return hit;
	}
	if (point_in_rect(x, y, &panel.layout_model.wsm_load_slot)) {
		hit.role = PANEL_HIT_WSM_LOAD;
		return hit;
	}
	if (point_in_rect(x, y, &panel.layout_model.wsm_exit_slot)) {
		hit.role = PANEL_HIT_WSM_EXIT;
		return hit;
	}

	for (int i = 0; i < panel.launcher_count; i++) {
		struct launcher_button *lb = &panel.launchers[i];
		struct section_rect trigger = {
			.x = lb->x,
			.y = lb->trigger_y,
			.w = lb->width,
			.h = lb->trigger_h,
		};
		struct section_rect body = {
			.x = lb->x,
			.y = lb->body_y,
			.w = lb->width,
			.h = lb->body_h,
		};
		if (point_in_rect(x, y, &trigger)) {
			hit.role = PANEL_HIT_LAUNCHER_TRIGGER;
			hit.index = i;
			return hit;
		}
		if (point_in_rect(x, y, &body)) {
			hit.role = PANEL_HIT_LAUNCHER_BODY;
			hit.index = i;
			return hit;
		}
	}

	for (int i = 0; i < panel.applet_count; i++) {
		struct applet_slot *as = &panel.applets[i];
		if (as->is_launcher) {
			struct section_rect trigger = {
				.x = as->x,
				.y = as->trigger_y,
				.w = as->width,
				.h = as->trigger_h,
			};
			struct section_rect body = {
				.x = as->x,
				.y = as->body_y,
				.w = as->width,
				.h = as->body_h,
			};
			if (point_in_rect(x, y, &trigger)) {
				hit.role = PANEL_HIT_RIGHT_LAUNCHER_TRIGGER;
				hit.index = i;
				return hit;
			}
			if (point_in_rect(x, y, &body)) {
				hit.role = PANEL_HIT_RIGHT_LAUNCHER_BODY;
				hit.index = i;
				return hit;
			}
		} else {
			struct section_rect slot = {
				.x = as->x,
				.y = as->trigger_y,
				.w = as->width,
				.h = as->trigger_h + as->body_h,
			};
			if (point_in_rect(x, y, &slot)) {
				hit.role = PANEL_HIT_APPLET;
				hit.index = i;
				return hit;
			}
		}
	}

	for (int i = 0; i < panel.workspace_count; i++) {
		struct section_rect ws = {
			.x = panel.workspaces[i].x,
			.y = panel.workspaces[i].y,
			.w = panel.workspaces[i].width,
			.h = panel.workspaces[i].height,
		};
		if (point_in_rect(x, y, &ws)) {
			hit.role = PANEL_HIT_WORKSPACE;
			hit.index = i;
			return hit;
		}
	}

	return hit;
}

static struct panel_hit_result
hit_test_subpanel(int x, int y)
{
	struct panel_hit_result hit = { PANEL_HIT_NONE, -1, -1 };
	int rel_y;
	int entry_idx;

	if (!panel.sp_surface.open || panel.active_subpanel < 0 ||
		!panel.sp_surface.configured) {
		return hit;
	}
	if (x < 0 || y < 0 ||
		x >= (int)panel.sp_surface.width ||
		y >= (int)panel.sp_surface.height) {
		return hit;
	}

	rel_y = y - panel.layout_subpanel_padding - panel.layout_subpanel_title_height;
	if (rel_y < 0) {
		return hit;
	}

	entry_idx = rel_y / panel.layout_subpanel_entry_height;
	if (entry_idx < 0 || entry_idx >= panel.subpanels[panel.active_subpanel].entry_count) {
		return hit;
	}

	hit.role = PANEL_HIT_SUBPANEL_ENTRY;
	hit.index = entry_idx;
	hit.sub_index = panel.active_subpanel;
	return hit;
}

static void
dispatch_wsm_slot_action(enum panel_hit_role role, uint32_t button)
{
	if (button != BTN_LEFT && button != BTN_MIDDLE && button != BTN_RIGHT) {
		return;
	}

	switch (role) {
	case PANEL_HIT_WSM_LOCK:
		if (button == BTN_LEFT) {
			execute_launcher_command("xscreensaver-command -lock");
		} else if (button == BTN_MIDDLE) {
			execute_launcher_command("xscreensaver-demo");
		}
		break;
	case PANEL_HIT_WSM_PGM:
		if (button == BTN_LEFT) {
			execute_launcher_command("QT_QPA_PLATFORM=wayland ${NSCDE_TOOLSDIR}/nscde_labwc_wsm");
		} else if (button == BTN_MIDDLE) {
			execute_launcher_command("QT_QPA_PLATFORM=wayland ${NSCDE_TOOLSDIR}/nscde_stylemgr wsm");
		}
		break;
	case PANEL_HIT_WSM_LOAD:
		if (button == BTN_LEFT) {
			execute_launcher_command("QT_QPA_PLATFORM=wayland ${NSCDE_TOOLSDIR}/nscde_labwc_sysinfo");
		}
		break;
	case PANEL_HIT_WSM_EXIT:
		if (button == BTN_LEFT) {
			execute_launcher_command("QT_QPA_PLATFORM=wayland ${NSCDE_TOOLSDIR}/nscde_labwc_sysaction");
		}
		break;
	case PANEL_HIT_NONE:
	case PANEL_HIT_SUBPANEL_ENTRY:
	case PANEL_HIT_RIGHT_LAUNCHER_TRIGGER:
	case PANEL_HIT_RIGHT_LAUNCHER_BODY:
	case PANEL_HIT_LAUNCHER_TRIGGER:
	case PANEL_HIT_LAUNCHER_BODY:
	case PANEL_HIT_APPLET:
	case PANEL_HIT_WORKSPACE:
	default:
		break;
	}
}

static void
dispatch_panel_chrome_action(enum panel_hit_role role, uint32_t button)
{
	if (button != BTN_LEFT && button != BTN_MIDDLE && button != BTN_RIGHT) {
		return;
	}

	switch (role) {
	case PANEL_HIT_LEFT_MENU_BUTTON:
	case PANEL_HIT_LEFT_HANDLE:
	case PANEL_HIT_RIGHT_ICONIFY_BUTTON:
	case PANEL_HIT_RIGHT_HANDLE:
		break;
	case PANEL_HIT_NONE:
	case PANEL_HIT_SUBPANEL_ENTRY:
	case PANEL_HIT_WSM_LOCK:
	case PANEL_HIT_WSM_PGM:
	case PANEL_HIT_WSM_LOAD:
	case PANEL_HIT_WSM_EXIT:
	case PANEL_HIT_RIGHT_LAUNCHER_TRIGGER:
	case PANEL_HIT_RIGHT_LAUNCHER_BODY:
	case PANEL_HIT_LAUNCHER_TRIGGER:
	case PANEL_HIT_LAUNCHER_BODY:
	case PANEL_HIT_APPLET:
	case PANEL_HIT_WORKSPACE:
	default:
		break;
	}
}

static void
dispatch_panel_hit(const struct panel_hit_result *hit, uint32_t button)
{
	if (!hit) {
		return;
	}

	if (panel.sp_surface.open && panel.active_subpanel >= 0 &&
		hit->role != PANEL_HIT_SUBPANEL_ENTRY &&
		hit->role != PANEL_HIT_LAUNCHER_TRIGGER &&
		hit->role != PANEL_HIT_RIGHT_LAUNCHER_TRIGGER) {
		close_subpanel();
	}

	switch (hit->role) {
	case PANEL_HIT_SUBPANEL_ENTRY:
		if (button == BTN_LEFT &&
			hit->sub_index >= 0 && hit->sub_index < panel.subpanel_count &&
			hit->index >= 0 &&
			hit->index < panel.subpanels[hit->sub_index].entry_count) {
			execute_launcher_command(
				panel.subpanels[hit->sub_index].entries[hit->index].command);
			close_subpanel();
		}
		break;
	case PANEL_HIT_LEFT_MENU_BUTTON:
	case PANEL_HIT_LEFT_HANDLE:
	case PANEL_HIT_RIGHT_ICONIFY_BUTTON:
	case PANEL_HIT_RIGHT_HANDLE:
		dispatch_panel_chrome_action(hit->role, button);
		break;
	case PANEL_HIT_WSM_LOCK:
	case PANEL_HIT_WSM_PGM:
	case PANEL_HIT_WSM_LOAD:
	case PANEL_HIT_WSM_EXIT:
		dispatch_wsm_slot_action(hit->role, button);
		break;
	case PANEL_HIT_LAUNCHER_TRIGGER:
		if (button == BTN_LEFT &&
			hit->index >= 0 && hit->index < panel.launcher_count &&
			panel.launchers[hit->index].subpanel_idx >= 0) {
			open_subpanel(panel.launchers[hit->index].subpanel_idx);
		}
		break;
	case PANEL_HIT_LAUNCHER_BODY:
		if (button == BTN_LEFT &&
			hit->index >= 0 && hit->index < panel.launcher_count) {
			execute_launcher_command(panel.launchers[hit->index].command);
		} else if (button == BTN_MIDDLE &&
			hit->index >= 0 && hit->index < panel.launcher_count &&
			strcmp(panel.launchers[hit->index].module, "style") == 0) {
			execute_launcher_command("QT_QPA_PLATFORM=wayland ${NSCDE_TOOLSDIR}/nscde_stylemgr backdrop");
		}
		break;
	case PANEL_HIT_RIGHT_LAUNCHER_TRIGGER:
		if (button == BTN_LEFT &&
			hit->index >= 0 && hit->index < panel.applet_count &&
			panel.applets[hit->index].subpanel_idx >= 0 &&
			panel.applets[hit->index].subpanel_idx < panel.subpanel_count &&
			panel.subpanels[panel.applets[hit->index].subpanel_idx].enabled &&
			panel.subpanels[panel.applets[hit->index].subpanel_idx].entry_count > 0) {
			open_subpanel(panel.applets[hit->index].subpanel_idx);
		}
		break;
	case PANEL_HIT_RIGHT_LAUNCHER_BODY:
		if (button == BTN_LEFT &&
			hit->index >= 0 && hit->index < panel.applet_count &&
			panel.applets[hit->index].command[0]) {
			execute_launcher_command(panel.applets[hit->index].command);
		} else if (button == BTN_MIDDLE &&
			hit->index >= 0 && hit->index < panel.applet_count &&
			strcmp(panel.applets[hit->index].name, "style") == 0) {
			execute_launcher_command("QT_QPA_PLATFORM=wayland ${NSCDE_TOOLSDIR}/nscde_stylemgr backdrop");
		}
		break;
	case PANEL_HIT_APPLET:
		if (button == BTN_LEFT &&
			hit->index >= 0 && hit->index < panel.applet_count &&
			panel.applets[hit->index].command[0]) {
			execute_launcher_command(panel.applets[hit->index].command);
		}
		break;
	case PANEL_HIT_WORKSPACE:
		if (button == BTN_LEFT &&
			hit->index >= 0 && hit->index < panel.workspace_count) {
			send_workspace_switch(panel.workspaces[hit->index].name);
		}
		break;
	case PANEL_HIT_NONE:
	default:
		break;
	}
}

static void
render_section_center_wsm(cairo_t *cr, const struct section_rect *r,
	PangoLayout *layout, PangoFontDescription *ws_font,
	const struct cde_palette *pal, int bw)
{
	struct panel_button_style load_style;
	const struct cde_palette *button_pal = &panel.fp_button_palette;
	int section_h = r->h - panel.layout_bottom_strip_height;

	if (section_h < 1) {
		section_h = r->h;
	}

	fill_inner_section_slab(cr, r->x, r->y, r->w, section_h, pal);
	draw_bevel_rect(cr, r->x, r->y, r->w, section_h,
		pal->hi, pal->sh, bw);
	frontpanel_button_style(&load_style, button_pal, FP_BUTTON_SUNKEN);
	draw_panel_decorated_button(cr, &panel.layout_model.wsm_load_slot,
		&load_style, 1, pal);

	if (!nscde_pixel_icon_render_asset(&panel.pixel_icons, cr,
			"icons/NsCDE/FpLock.xpm",
			panel.layout_model.wsm_lock_icon.x,
			panel.layout_model.wsm_lock_icon.y,
			panel.layout_model.wsm_lock_icon.w,
			panel.layout_model.wsm_lock_icon.h)) {
		cairo_set_source_rgba_array(cr, pal->sfg);
		cairo_rectangle(cr,
			panel.layout_model.wsm_lock_slot.x + panel.layout_model.wsm_lock_slot.w / 2 - 6,
			panel.layout_model.wsm_lock_slot.y + 9,
			12, 10);
		cairo_stroke(cr);
		cairo_arc(cr,
			panel.layout_model.wsm_lock_slot.x + panel.layout_model.wsm_lock_slot.w / 2,
			panel.layout_model.wsm_lock_slot.y + 9,
			5, M_PI, 2 * M_PI);
		cairo_stroke(cr);
	}

	nscde_pixel_icon_render_asset(&panel.pixel_icons, cr,
		"icons/NsCDE/Wsm.xpm",
		panel.layout_model.wsm_pgm_icon.x,
		panel.layout_model.wsm_pgm_icon.y,
		panel.layout_model.wsm_pgm_icon.w,
		panel.layout_model.wsm_pgm_icon.h);

	cairo_set_source_rgba(cr, 0.75, 0.8, 0.2, 1.0);
	cairo_rectangle(cr,
		panel.layout_model.wsm_load_slot.x + 3,
		panel.layout_model.wsm_load_slot.y + 3,
		(panel.layout_model.wsm_load_slot.w - 6)
			* panel.applet_live.load_bar_pct / 100,
		panel.layout_model.wsm_load_slot.h - 6);
	cairo_fill(cr);

	if (!nscde_pixel_icon_render_asset(&panel.pixel_icons, cr,
			"icons/NsCDE/FpExit.xpm",
			panel.layout_model.wsm_exit_icon.x,
			panel.layout_model.wsm_exit_icon.y,
			panel.layout_model.wsm_exit_icon.w,
			panel.layout_model.wsm_exit_icon.h)) {
		pango_layout_set_font_description(layout, ws_font);
		pango_layout_set_text(layout, "EXIT", -1);
		int exit_tw, exit_th;
		pango_layout_get_pixel_size(layout, &exit_tw, &exit_th);
		cairo_set_source_rgba_array(cr, pal->sfg);
		cairo_move_to(cr,
			panel.layout_model.wsm_exit_slot.x
			+ (panel.layout_model.wsm_exit_slot.w - exit_tw) / 2,
			panel.layout_model.wsm_exit_slot.y
			+ (panel.layout_model.wsm_exit_slot.h - exit_th) / 2);
		pango_cairo_show_layout(cr, layout);
	}

	pango_layout_set_font_description(layout, ws_font);
	for (int i = 0; i < panel.workspace_count; i++) {
		struct ws_button *btn = &panel.workspaces[i];
		struct panel_button_style style;
		int cell_x = btn->x;
		int cell_y = btn->y;
		pango_layout_set_text(layout, btn->name, -1);
		int text_w, text_h;
		pango_layout_get_pixel_size(layout, &text_w, &text_h);
		workspace_button_style(&style, pal, i, btn->active);
		struct section_rect rect = {
			.x = cell_x,
			.y = cell_y,
			.w = btn->width,
			.h = btn->height,
		};
		draw_panel_decorated_button(cr, &rect, &style, 1, pal);

		cairo_set_source_rgba_array(cr, style.fgsh);
		cairo_move_to(cr,
			cell_x + (btn->width - text_w) / 2 + 1,
			cell_y + (btn->height - text_h) / 2 + 1);
		pango_layout_set_text(layout, btn->name, -1);
		pango_cairo_show_layout(cr, layout);
		cairo_set_source_rgba_array(cr, style.fg);
		cairo_move_to(cr,
			cell_x + (btn->width - text_w) / 2,
			cell_y + (btn->height - text_h) / 2);
		pango_layout_set_text(layout, btn->name, -1);
		pango_cairo_show_layout(cr, layout);
	}
}

static void
render_section_right_bank(cairo_t *cr, const struct section_rect *r,
		PangoLayout *layout, const struct cde_palette *pal, int bw)
{
	struct panel_button_style button_style;
	const struct cde_palette *button_pal = &panel.fp_button_palette;
	int trigger_y = r->y - panel.layout_trigger_height;

	fill_inner_section_slab(cr, r->x, trigger_y,
		r->w, panel.layout_trigger_height + r->h, pal);
	if (r->h > 0) {
		draw_bevel_rect(cr, r->x, r->y, r->w, r->h,
			pal->hi, pal->sh, bw);
	}
	cairo_set_source_rgba_array(cr, pal->sh);
	cairo_rectangle(cr, r->x,
		trigger_y + panel.layout_trigger_height + r->h - 1,
		r->w, 1);
	cairo_fill(cr);
	frontpanel_button_style(&button_style, button_pal, FP_BUTTON_NORMAL);

	for (int i = panel.applet_count - 1; i >= 0; i--) {
		struct applet_slot *as = &panel.applets[i];
		int aw = as->width;
		int ah = as->height;
		int applet_x = as->x;
		int ay = as->body_y + (as->body_h - ah) / 2;

		draw_trigger_slot(cr, applet_x, as->trigger_y, aw,
			as->trigger_h, pal);
		draw_trigger_marker(cr,
			applet_x + aw / 2,
			as->trigger_y + as->trigger_h / 2,
			4,
			pal);

		struct section_rect body_rect = {
			.x = applet_x,
			.y = as->body_y,
			.w = aw,
			.h = as->body_h,
		};

		if (as->is_launcher) {
			struct launcher_button pseudo = {0};
			strncpy(pseudo.module, as->name, sizeof(pseudo.module) - 1);
			strncpy(pseudo.label, as->label, sizeof(pseudo.label) - 1);
			pseudo.width = aw;
			pseudo.icon_size = panel.layout_launcher_icon_size;
			pseudo.content_type = APPLET_UNKNOWN;
			pseudo.trigger_y = as->trigger_y;
			pseudo.trigger_h = as->trigger_h;
			pseudo.body_y = as->body_y;
			pseudo.body_h = as->body_h;
			render_module_in_launcher_body(cr, &pseudo, layout, button_pal,
				applet_x, as->body_y, as->body_h);
			continue;
		}

		switch (as->type) {
		case APPLET_CLOCK:
				render_applet_clock(cr,
					applet_x + aw / 2,
					ay + ah / 2,
					ah, button_pal);
				break;
			case APPLET_DATE:
				render_applet_date(cr, layout,
					applet_x, ay,
					aw, ah, button_pal);
				break;
			case APPLET_MAIL:
				render_applet_mail(cr,
					applet_x, ay,
					aw, ah, button_pal);
				break;
			case APPLET_LOAD:
				render_applet_load(cr,
					applet_x, ay,
					aw, ah, button_pal);
				break;
		default:
			/* Unknown applet: draw placeholder */
			cairo_set_source_rgba_array(cr, pal->bg);
			cairo_rectangle(cr, applet_x, ay,
				aw, ah);
			cairo_fill(cr);
			draw_bevel_rect(cr, applet_x, ay,
				aw, ah, pal->hi, pal->sh, 1);
			break;
		}

	}
}

static void
render_section_right_handle(cairo_t *cr, const struct section_rect *r,
	const struct cde_palette *pal, int bw)
{
	cairo_set_source_rgba_array(cr, pal->bg);
	cairo_rectangle(cr, r->x, r->y, r->w, r->h);
	cairo_fill(cr);
	draw_bevel_rect(cr, r->x, r->y, r->w, r->h,
		pal->hi, pal->sh, bw);
	draw_handle_reference_gaps(cr, r,
		&panel.layout_model.right_handle_button, true);

	draw_handle_button_slot(cr,
		panel.layout_model.right_handle_button.x,
		panel.layout_model.right_handle_button.y,
		panel.layout_model.right_handle_button.w,
		panel.layout_model.right_handle_button.h,
		pal);
	if (!render_asset_centered_native(cr, "icons/NsCDE/FpIconify.xpm",
			&panel.layout_model.right_handle_button)) {
		draw_handle_button_glyph(cr,
			panel.layout_model.right_handle_button.x,
			panel.layout_model.right_handle_button.y,
			panel.layout_model.right_handle_button.w,
			panel.layout_model.right_handle_button.h,
			pal,
			false);
	}
	if (!nscde_pixel_icon_render_asset(&panel.pixel_icons, cr,
			"icons/NsCDE/FpHandle.xpm",
			panel.layout_model.right_handle_grip.x,
			panel.layout_model.right_handle_grip.y,
			panel.layout_model.right_handle_grip.w,
			panel.layout_model.right_handle_grip.h)) {
		draw_handle_grip(cr,
			panel.layout_model.right_handle.x,
			panel.layout_model.right_handle_grip.y,
			panel.layout_model.right_handle.w,
			panel.layout_model.right_handle_grip.h,
			pal);
	}
}

static void
render_section_bottom_strip(cairo_t *cr, const struct section_rect *r,
	const struct cde_palette *pal)
{
	/* Bottom correction strip: dark gap color (FVWM Colorset 15) */
	cairo_set_source_rgba_array(cr, panel.fp_gap_dark);
	cairo_rectangle(cr, r->x, r->y, r->w, r->h);
	cairo_fill(cr);
}

static void
render_panel(cairo_t *cr)
{
	struct cde_palette *pal = &panel.palette;
	uint32_t w = panel.width;
	uint32_t h = panel.height;
	int bw = panel.layout_bevel_width;
	int margin = panel.layout_margin;
	int border = panel.layout_border_width;
	nscde_pixel_icon_set_palette(&panel.pixel_icons,
		((uint32_t)(panel.fp_button_palette.bg[3] * 255.0) << 24)
		| ((uint32_t)(panel.fp_button_palette.bg[0] * 255.0) << 16)
		| ((uint32_t)(panel.fp_button_palette.bg[1] * 255.0) << 8)
		| (uint32_t)(panel.fp_button_palette.bg[2] * 255.0),
		((uint32_t)(panel.fp_button_palette.hi[3] * 255.0) << 24)
		| ((uint32_t)(panel.fp_button_palette.hi[0] * 255.0) << 16)
		| ((uint32_t)(panel.fp_button_palette.hi[1] * 255.0) << 8)
		| (uint32_t)(panel.fp_button_palette.hi[2] * 255.0),
		((uint32_t)(panel.fp_button_palette.sh[3] * 255.0) << 24)
		| ((uint32_t)(panel.fp_button_palette.sh[0] * 255.0) << 16)
		| ((uint32_t)(panel.fp_button_palette.sh[1] * 255.0) << 8)
		| (uint32_t)(panel.fp_button_palette.sh[2] * 255.0),
		((uint32_t)(panel.fp_button_palette.sel[3] * 255.0) << 24)
		| ((uint32_t)(panel.fp_button_palette.sel[0] * 255.0) << 16)
		| ((uint32_t)(panel.fp_button_palette.sel[1] * 255.0) << 8)
		| (uint32_t)(panel.fp_button_palette.sel[2] * 255.0));

	/* Clear */
	cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR);
	cairo_paint(cr);
	cairo_set_operator(cr, CAIRO_OPERATOR_OVER);

	/* Panel background (secondary bg) */
	cairo_set_source_rgba_array(cr, pal->bg);
	cairo_rectangle(cr, 0, 0, w, h);
	cairo_fill(cr);

	/* Outer raised bevel */
	draw_bevel_rect(cr, 0, 0, w, h, pal->hi, pal->sh, bw);

	/* Set up pango for text rendering */
	PangoLayout *layout = pango_cairo_create_layout(cr);
	PangoFontDescription *font_desc =
		make_scaled_font_description(panel.layout_font);
	pango_layout_set_font_description(layout, font_desc);

	/* Workspace button font: FVWM uses pixelsize=14 */
	PangoFontDescription *ws_font =
		make_pixel_font_description(panel.layout_ws_font);

	compute_panel_layout_model(&panel.layout_model);

	/* ---- Draw sections ---- */
	render_section_left_handle(cr, &panel.layout_model.left_handle, pal, bw);
	render_section_left_bank(cr, &panel.layout_model.left_bank, layout, font_desc, pal, bw);
	render_section_center_wsm(cr, &panel.layout_model.center, layout, ws_font, pal, bw);
	render_section_right_bank(cr, &panel.layout_model.right_bank, layout, pal, bw);
	render_section_right_handle(cr, &panel.layout_model.right_handle, pal, bw);
	render_section_bottom_strip(cr, &panel.layout_model.bottom_strip, pal);

	pango_font_description_free(ws_font);
	pango_font_description_free(font_desc);
	g_object_unref(layout);
}

/* ---- Subpanel surface management ---- */

static void
subpanel_layer_surface_configure(void *data,
	struct zwlr_layer_surface_v1 *surface,
	uint32_t serial, uint32_t width, uint32_t height)
{
	struct subpanel_surface *sp = data;
	if (width > 0) {
		sp->width = width;
	}
	if (height > 0) {
		sp->height = height;
	}
	zwlr_layer_surface_v1_ack_configure(surface, serial);
	sp->configured = true;
	render_subpanel_surface();
}

static void
subpanel_layer_surface_closed(void *data,
	struct zwlr_layer_surface_v1 *surface)
{
	struct subpanel_surface *sp = data;
	sp->open = false;
	panel.active_subpanel = -1;
}

static const struct zwlr_layer_surface_v1_listener subpanel_layer_surface_listener = {
	.configure = subpanel_layer_surface_configure,
	.closed = subpanel_layer_surface_closed,
};

static void
close_subpanel(void)
{
	struct subpanel_surface *sp = &panel.sp_surface;
	if (!sp->open) {
		return;
	}

	if (sp->layer_surface) {
		zwlr_layer_surface_v1_destroy(sp->layer_surface);
		sp->layer_surface = NULL;
	}
	if (sp->surface) {
		wl_surface_destroy(sp->surface);
		sp->surface = NULL;
	}
	destroy_buffer(&sp->buffers[0]);
	destroy_buffer(&sp->buffers[1]);
	memset(sp->buffers, 0, sizeof(sp->buffers));

	sp->open = false;
	sp->configured = false;
	panel.active_subpanel = -1;
}

static void
open_subpanel(int sp_idx)
{
	struct subpanel_surface *sp = &panel.sp_surface;

	/* If this subpanel is already open, close it (toggle) */
	if (sp->open && panel.active_subpanel == sp_idx) {
		close_subpanel();
		return;
	}

	/* Close any existing subpanel first */
	if (sp->open) {
		close_subpanel();
	}

	if (sp_idx < 0 || sp_idx >= MAX_SUBPANELS) {
		return;
	}
	struct subpanel_def *spd = &panel.subpanels[sp_idx];
	if (!spd->enabled || spd->entry_count <= 0) {
		return;
	}

	/* Calculate subpanel dimensions */
	int pad = panel.layout_subpanel_padding;
	int entry_h = panel.layout_subpanel_entry_height;
	int title_h = panel.layout_subpanel_title_height;
	sp->width = spd->width;
	sp->height = title_h + spd->entry_count * entry_h + pad * 2;
	sp->scale = panel.scale;
	sp->subpanel_idx = sp_idx;

	/* Create new Wayland surface */
	sp->surface = wl_compositor_create_surface(panel.compositor);
	if (!sp->surface) {
		fprintf(stderr, "nscde_paneld: failed to create subpanel surface\n");
		return;
	}

	/* Create layer surface on overlay layer, no exclusive zone */
	sp->layer_surface = zwlr_layer_shell_v1_get_layer_surface(
		panel.layer_shell, sp->surface, NULL,
		ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY,
		"nscde-subpanel");
	if (!sp->layer_surface) {
		fprintf(stderr, "nscde_paneld: failed to create subpanel layer surface\n");
		wl_surface_destroy(sp->surface);
		sp->surface = NULL;
		return;
	}

	zwlr_layer_surface_v1_add_listener(sp->layer_surface,
		&subpanel_layer_surface_listener, sp);

	/* Position below the panel, aligned to the launcher */
	/* Find the launcher that maps to this subpanel */
	int launcher_x = 0;
	int margin = panel.layout_margin;
	int bw = panel.layout_bevel_width;
	int lx = margin + bw + panel.layout_left_handle_width;
	int lg = panel.layout_launcher_gap;
	for (int i = 0; i < panel.launcher_count; i++) {
		if (panel.launchers[i].subpanel_idx == sp_idx) {
			launcher_x = lx;
			break;
		}
		lx += panel.launchers[i].width + lg;
	}

	/* Anchor to top and left, position below panel */
	zwlr_layer_surface_v1_set_anchor(sp->layer_surface,
		ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
		ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT);
	zwlr_layer_surface_v1_set_exclusive_zone(sp->layer_surface, 0);
	zwlr_layer_surface_v1_set_size(sp->layer_surface,
		sp->width, sp->height);
	/* Margin: top = panel height, left = launcher x offset */
	zwlr_layer_surface_v1_set_margin(sp->layer_surface,
		panel.height, 0, 0, launcher_x);

	/* Keyboard interactivity for focus tracking */
	zwlr_layer_surface_v1_set_keyboard_interactivity(sp->layer_surface, 1);

	wl_surface_commit(sp->surface);
	wl_display_roundtrip(panel.display);

	sp->open = true;
	sp->configured = true;
	panel.active_subpanel = sp_idx;
	render_subpanel_surface();
}

static void
render_subpanel_surface(void)
{
	struct subpanel_surface *sp = &panel.sp_surface;
	if (!sp->open || !sp->configured) {
		return;
	}
	int sp_idx = sp->subpanel_idx;
	if (sp_idx < 0 || sp_idx >= MAX_SUBPANELS) {
		return;
	}
	struct subpanel_def *spd = &panel.subpanels[sp_idx];

	sp->current_buffer = get_next_buffer(panel.shm,
		sp->buffers,
		sp->width * sp->scale,
		sp->height * sp->scale);
	if (!sp->current_buffer) {
		return;
	}

	cairo_t *cr = sp->current_buffer->cairo;
	cairo_save(cr);
	cairo_scale(cr, sp->scale, sp->scale);

	struct cde_palette *pal = &panel.palette;
	int w = sp->width;
	int h = sp->height;
	int pad = panel.layout_subpanel_padding;
	int entry_h = panel.layout_subpanel_entry_height;
	int title_h = panel.layout_subpanel_title_height;
	int icon_sz = panel.layout_subpanel_icon_size;
	int bw = panel.layout_bevel_width;

	/* Clear */
	cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR);
	cairo_paint(cr);
	cairo_set_operator(cr, CAIRO_OPERATOR_OVER);

	/* Background */
	cairo_set_source_rgba_array(cr, pal->sbg);
	cairo_rectangle(cr, 0, 0, w, h);
	cairo_fill(cr);

	/* Outer raised bevel */
	draw_bevel_rect(cr, 0, 0, w, h, pal->hi, pal->sh, bw);

	/* Title bar */
	cairo_set_source_rgba_array(cr, pal->acc);
	cairo_rectangle(cr, bw, bw, w - 2 * bw, title_h);
	cairo_fill(cr);
	draw_bevel_rect(cr, bw, bw, w - 2 * bw, title_h,
		pal->hi, pal->sh, 1);

	/* Title text -- FVWM: DejaVu Serif size=10 with shadow */
	PangoLayout *layout = pango_cairo_create_layout(cr);
	PangoFontDescription *font_desc =
		make_scaled_font_description("DejaVu Serif Bold 10");
	pango_layout_set_font_description(layout, font_desc);
	pango_layout_set_text(layout, spd->name, -1);
	int tw, th;
	pango_layout_get_pixel_size(layout, &tw, &th);
	cairo_set_source_rgba(cr, 1, 1, 1, 1);
	cairo_move_to(cr, bw + pad + 2, bw + (title_h - th) / 2);
	pango_cairo_show_layout(cr, layout);

	/* Entry rows */
	int y = bw + title_h + pad;
	for (int i = 0; i < spd->entry_count; i++) {
		struct subpanel_entry *se = &spd->entries[i];
		int row_x = bw + pad;
		int row_w = w - 2 * (bw + pad);

		/* Entry background (hover will be handled in pointer) */
		cairo_set_source_rgba_array(cr, pal->sbg);
		cairo_rectangle(cr, row_x, y, row_w, entry_h);
		cairo_fill(cr);

		/* Icon placeholder square */
		int icon_x = row_x + 2;
		int icon_y = y + (entry_h - icon_sz) / 2;
		cairo_set_source_rgba_array(cr, pal->sel);
		cairo_rectangle(cr, icon_x, icon_y, icon_sz, icon_sz);
		cairo_fill(cr);
		draw_bevel_rect(cr, icon_x, icon_y, icon_sz, icon_sz,
			pal->hi, pal->sh, 1);

		/* Entry title text -- FVWM: DejaVu Serif size=10 */
		PangoFontDescription *entry_font =
			make_scaled_font_description("DejaVu Serif 10");
		pango_layout_set_font_description(layout, entry_font);
		pango_layout_set_text(layout, se->title, -1);
		int etw, eth;
		pango_layout_get_pixel_size(layout, &etw, &eth);
		cairo_set_source_rgba_array(cr, pal->sfg);
		cairo_move_to(cr, icon_x + icon_sz + 4,
			y + (entry_h - eth) / 2);
		pango_cairo_show_layout(cr, layout);
		pango_font_description_free(entry_font);

		y += entry_h;
	}

	pango_font_description_free(font_desc);
	g_object_unref(layout);
	cairo_restore(cr);

	wl_surface_set_buffer_scale(sp->surface, sp->scale);
	wl_surface_attach(sp->surface, sp->current_buffer->buffer, 0, 0);
	wl_surface_damage(sp->surface, 0, 0, sp->width, sp->height);
	wl_surface_commit(sp->surface);
}

/* ---- Frame callback ---- */

static void
surface_frame_callback(void *data, struct wl_callback *callback,
	uint32_t time);

static const struct wl_callback_listener frame_listener = {
	.done = surface_frame_callback,
};

static void
render_and_commit(void)
{
	if (!panel.configured || !panel.running) {
		return;
	}

	panel.current_buffer = get_next_buffer(panel.shm,
		panel.buffers,
		panel.width * panel.scale,
		panel.height * panel.scale);
	if (!panel.current_buffer) {
		return;
	}

	cairo_t *cr = panel.current_buffer->cairo;
	cairo_save(cr);
	cairo_scale(cr, panel.scale, panel.scale);
	render_panel(cr);
	cairo_restore(cr);

	wl_surface_set_buffer_scale(panel.surface, panel.scale);
	wl_surface_attach(panel.surface,
		panel.current_buffer->buffer, 0, 0);
	wl_surface_damage(panel.surface, 0, 0,
		panel.width, panel.height);

	struct wl_callback *callback = wl_surface_frame(panel.surface);
	wl_callback_add_listener(callback, &frame_listener, NULL);
	panel.frame_pending = true;

	wl_surface_commit(panel.surface);
}

static void
surface_frame_callback(void *data, struct wl_callback *callback,
	uint32_t time)
{
	wl_callback_destroy(callback);
	panel.frame_pending = false;
	if (panel.dirty) {
		render_and_commit();
		panel.dirty = false;
	}
}

/* ---- Pointer state ---- */
static int pointer_x;
static int pointer_y;

/* ---- Wayland callbacks ---- */

static void
layer_surface_configure(void *data,
	struct zwlr_layer_surface_v1 *surface,
	uint32_t serial, uint32_t width, uint32_t height)
{
	if (width > 0) {
		panel.width = width;
	}
	if (height > 0) {
		panel.height = height;
	}
	zwlr_layer_surface_v1_ack_configure(surface, serial);
	panel.configured = true;
	panel.dirty = true;
	render_and_commit();
}

static void
layer_surface_closed(void *data,
	struct zwlr_layer_surface_v1 *surface)
{
	panel.running = false;
}

static const struct zwlr_layer_surface_v1_listener layer_surface_listener = {
	.configure = layer_surface_configure,
	.closed = layer_surface_closed,
};

static void
pointer_enter(void *data, struct wl_pointer *pointer,
	uint32_t serial, struct wl_surface *surface,
	wl_fixed_t sx, wl_fixed_t sy)
{
	pointer_focus_surface = surface;
	pointer_x = wl_fixed_to_int(sx);
	pointer_y = wl_fixed_to_int(sy);
}

static void
pointer_leave(void *data, struct wl_pointer *pointer,
	uint32_t serial, struct wl_surface *surface)
{
	if (pointer_focus_surface == surface) {
		pointer_focus_surface = NULL;
	}
}

static void
pointer_motion(void *data, struct wl_pointer *pointer,
	uint32_t time, wl_fixed_t sx, wl_fixed_t sy)
{
	pointer_x = wl_fixed_to_int(sx);
	pointer_y = wl_fixed_to_int(sy);
}

static void
pointer_button(void *data, struct wl_pointer *pointer,
	uint32_t serial, uint32_t time, uint32_t button,
	uint32_t state)
{
	struct panel_hit_result hit;

	if (state != WL_POINTER_BUTTON_STATE_PRESSED) {
		return;
	}

	if (pointer_focus_surface == panel.sp_surface.surface) {
		hit = hit_test_subpanel(pointer_x, pointer_y);
	} else {
		hit = hit_test_panel(pointer_x, pointer_y);
	}
	dispatch_panel_hit(&hit, button);
}

static void
pointer_axis(void *data, struct wl_pointer *pointer,
	uint32_t time, uint32_t axis, wl_fixed_t value)
{
}

static void
pointer_frame(void *data, struct wl_pointer *pointer)
{
}

static void
pointer_axis_source(void *data, struct wl_pointer *pointer,
	uint32_t axis_source)
{
}

static void
pointer_axis_stop(void *data, struct wl_pointer *pointer,
	uint32_t time, uint32_t axis)
{
}

static void
pointer_axis_discrete(void *data, struct wl_pointer *pointer,
	uint32_t axis, int32_t discrete)
{
}

static void
pointer_axis_value120(void *data, struct wl_pointer *pointer,
	uint32_t axis, int32_t value120)
{
}

static void
pointer_axis_relative_direction(void *data, struct wl_pointer *pointer,
	uint32_t axis, uint32_t direction)
{
}

static const struct wl_pointer_listener pointer_listener = {
	.enter = pointer_enter,
	.leave = pointer_leave,
	.motion = pointer_motion,
	.button = pointer_button,
	.axis = pointer_axis,
	.frame = pointer_frame,
	.axis_source = pointer_axis_source,
	.axis_stop = pointer_axis_stop,
	.axis_discrete = pointer_axis_discrete,
	.axis_value120 = pointer_axis_value120,
	.axis_relative_direction = pointer_axis_relative_direction,
};

static void
seat_capabilities(void *data, struct wl_seat *seat, uint32_t caps)
{
	if ((caps & WL_SEAT_CAPABILITY_POINTER) && !panel_pointer) {
		panel_pointer = wl_seat_get_pointer(seat);
		wl_pointer_add_listener(panel_pointer, &pointer_listener, NULL);
	} else if (!(caps & WL_SEAT_CAPABILITY_POINTER) && panel_pointer) {
		wl_pointer_destroy(panel_pointer);
		panel_pointer = NULL;
	}
}

static void
seat_name(void *data, struct wl_seat *seat, const char *name)
{
}

static const struct wl_seat_listener seat_listener = {
	.capabilities = seat_capabilities,
	.name = seat_name,
};

static void
output_scale(void *data, struct wl_output *output, int32_t factor)
{
	panel.scale = factor;
	panel.dirty = true;
}

static void
output_geometry(void *data, struct wl_output *output,
	int32_t x, int32_t y, int32_t physical_width,
	int32_t physical_height, int32_t subpixel,
	const char *make, const char *model, int32_t transform)
{
}

static void
output_mode(void *data, struct wl_output *output,
	uint32_t flags, int32_t width, int32_t height,
	int32_t refresh)
{
}

static void
output_done(void *data, struct wl_output *output)
{
}

static void
output_name(void *data, struct wl_output *output, const char *name)
{
}

static void
output_description(void *data, struct wl_output *output,
	const char *description)
{
}

static const struct wl_output_listener output_listener = {
	.geometry = output_geometry,
	.mode = output_mode,
	.done = output_done,
	.scale = output_scale,
	.name = output_name,
	.description = output_description,
};

static void
registry_global(void *data, struct wl_registry *registry,
	uint32_t name, const char *interface, uint32_t version)
{
	if (strcmp(interface, wl_compositor_interface.name) == 0) {
		panel.compositor = wl_registry_bind(registry, name,
			&wl_compositor_interface, 4);
	} else if (strcmp(interface, wl_shm_interface.name) == 0) {
		panel.shm = wl_registry_bind(registry, name,
			&wl_shm_interface, 1);
	} else if (strcmp(interface, wl_seat_interface.name) == 0) {
		panel.seat = wl_registry_bind(registry, name,
			&wl_seat_interface, 5);
		wl_seat_add_listener(panel.seat, &seat_listener, NULL);
	} else if (strcmp(interface, wl_output_interface.name) == 0) {
		struct wl_output *output = wl_registry_bind(registry, name,
			&wl_output_interface, 4);
		wl_output_add_listener(output, &output_listener, NULL);
	} else if (strcmp(interface, zwlr_layer_shell_v1_interface.name) == 0) {
		panel.layer_shell = wl_registry_bind(registry, name,
			&zwlr_layer_shell_v1_interface, 4);
	}
}

static void
registry_global_remove(void *data, struct wl_registry *registry,
	uint32_t name)
{
}

static const struct wl_registry_listener registry_listener = {
	.global = registry_global,
	.global_remove = registry_global_remove,
};

/* ---- FIFO command writing ---- */

static void
send_workspace_switch(const char *name)
{
	if (nscde_runtime_ctl_workspace_switch(name)) {
		return;
	}
	if (!panel.pager_fifo_path[0]) {
		return;
	}
	int fd = open(panel.pager_fifo_path, O_WRONLY | O_NONBLOCK);
	if (fd < 0) {
		return;
	}
	char cmd[MAX_NAME_LEN + 32];
	int len = snprintf(cmd, sizeof(cmd), "switch_workspace:%s\n", name);
	if (write(fd, cmd, len) < 0) {
		/* ignore */
	}
	close(fd);
}

static void
execute_launcher_command(const char *command)
{
	if (!command || !command[0]) {
		return;
	}
	/* Fork and exec the command in background */
	pid_t pid = fork();
	if (pid == 0) {
		/* Child process */
		setsid();
		execlp("sh", "sh", "-c", command, NULL);
		_exit(127);
	}
	/* Parent continues; ignore child exit */
}

/* ---- State file path setup ---- */

static void
setup_paths(void)
{
	const char *data_dir = getenv("NSCDE_DATADIR");
	const char *state_dir = getenv("NSCDE_STATE_DIR");
	char resolved_data_dir[PATH_MAX_LEN];
	if (data_dir && data_dir[0]) {
		strncpy(resolved_data_dir, data_dir, sizeof(resolved_data_dir) - 1);
		resolved_data_dir[sizeof(resolved_data_dir) - 1] = '\0';
	} else {
		const char *root = getenv("NSCDE_ROOT");
		if (root && root[0]) {
			snprintf(resolved_data_dir, sizeof(resolved_data_dir),
				"%s/share/NsCDE", root);
			resolved_data_dir[sizeof(resolved_data_dir) - 1] = '\0';
		} else {
			strncpy(resolved_data_dir, "NsCDE/data",
				sizeof(resolved_data_dir) - 1);
			resolved_data_dir[sizeof(resolved_data_dir) - 1] = '\0';
		}
	}
	nscde_pixel_icon_init(&panel.pixel_icons, resolved_data_dir);

	if (state_dir && state_dir[0]) {
		strncpy(panel.state_dir, state_dir, sizeof(panel.state_dir) - 1);
		panel.state_dir[sizeof(panel.state_dir) - 1] = '\0';
	} else {
		const char *cache_home = getenv("XDG_CACHE_HOME");
		if (!cache_home || !cache_home[0]) {
			const char *home = getenv("HOME");
			if (home) {
				static char cache_fallback[PATH_MAX_LEN];
				snprintf(cache_fallback, sizeof(cache_fallback),
					"%s/.cache", home);
				cache_home = cache_fallback;
			}
		}
		if (cache_home) {
			snprintf(panel.state_dir, sizeof(panel.state_dir),
				"%s/nscde-stage1", cache_home);
			panel.state_dir[sizeof(panel.state_dir) - 1] = '\0';
		}
	}

	if (panel.state_dir[0]) {
		snprintf(panel.panel_env_path, sizeof(panel.panel_env_path),
			"%s/panel.env", panel.state_dir);
		panel.panel_env_path[sizeof(panel.panel_env_path) - 1] = '\0';
		snprintf(panel.panel_layout_env_path,
			sizeof(panel.panel_layout_env_path),
			"%s/panel-layout.env", panel.state_dir);
		panel.panel_layout_env_path[
			sizeof(panel.panel_layout_env_path) - 1] = '\0';
		snprintf(panel.workspaces_env_path,
			sizeof(panel.workspaces_env_path),
			"%s/workspaces.env", panel.state_dir);
		panel.workspaces_env_path[
			sizeof(panel.workspaces_env_path) - 1] = '\0';
		snprintf(panel.subpanel_env_path,
			sizeof(panel.subpanel_env_path),
			"%s/subpanels.env", panel.state_dir);
		panel.subpanel_env_path[
			sizeof(panel.subpanel_env_path) - 1] = '\0';
	}
}

/* ---- Inotify and watchdog timer ---- */

static char *
duplicate_text(const char *text)
{
	size_t len;
	char *copy;

	if (!text) {
		return NULL;
	}

	len = strlen(text);
	copy = malloc(len + 1);
	if (!copy) {
		return NULL;
	}

	memcpy(copy, text, len + 1);
	return copy;
}

static char *
read_text_file(const char *path)
{
	FILE *f;
	size_t cap = 1024;
	size_t len = 0;
	char *contents;

	f = fopen(path, "r");
	if (!f) {
		return NULL;
	}

	contents = malloc(cap);
	if (!contents) {
		fclose(f);
		return NULL;
	}

	for (;;) {
		size_t remaining = cap - len;
		size_t bytes;

		if (remaining < 2) {
			char *grown;
			cap *= 2;
			grown = realloc(contents, cap);
			if (!grown) {
				free(contents);
				fclose(f);
				return NULL;
			}
			contents = grown;
			remaining = cap - len;
		}

		bytes = fread(contents + len, 1, remaining - 1, f);
		len += bytes;
		if (bytes == 0) {
			break;
		}
	}

	if (ferror(f)) {
		free(contents);
		fclose(f);
		return NULL;
	}

	contents[len] = '\0';
	fclose(f);
	return contents;
}

static void
setup_inotify(void)
{
	pollfds[FD_INOTIFY].fd = inotify_init1(IN_CLOEXEC | IN_NONBLOCK);
	pollfds[FD_INOTIFY].events = POLLIN;

	if (pollfds[FD_INOTIFY].fd < 0) {
		fprintf(stderr, "nscde_paneld: inotify_init1 failed: %s\n",
			strerror(errno));
		return;
	}

	if (panel.state_dir[0]) {
		int wd = inotify_add_watch(pollfds[FD_INOTIFY].fd,
			panel.state_dir,
			IN_CLOSE_WRITE | IN_MOVED_TO | IN_CREATE);
		if (wd < 0) {
			fprintf(stderr,
				"nscde_paneld: inotify_add_watch on %s failed: %s\n",
				panel.state_dir, strerror(errno));
		}
	}
}

static void
drain_inotify(void)
{
	char buf[4096]
		__attribute__((aligned(__alignof__(struct inotify_event))));
	for (;;) {
		ssize_t len = read(pollfds[FD_INOTIFY].fd, buf, sizeof(buf));
		if (len <= 0) {
			break;
		}
		/*
		 * We only need to know that something changed in the state
		 * directory; individual event parsing is not required since
		 * we unconditionally re-read both env files.
		 */
	}
}

static void
setup_watchdog_timer(void)
{
	pollfds[FD_TIMER].fd = timerfd_create(CLOCK_MONOTONIC, TFD_CLOEXEC);
	pollfds[FD_TIMER].events = POLLIN;
	struct itimerspec timer = {
		.it_interval.tv_sec = 30,
		.it_value.tv_sec = 30,
	};
	timerfd_settime(pollfds[FD_TIMER].fd, 0, &timer, NULL);
}

/* ---- Signal handling ---- */

static void
setup_signals(void)
{
	sigset_t mask;
	sigemptyset(&mask);
	sigaddset(&mask, SIGINT);
	sigaddset(&mask, SIGTERM);
	sigprocmask(SIG_BLOCK, &mask, NULL);
	pollfds[FD_SIGNAL].fd = signalfd(-1, &mask, SFD_CLOEXEC | SFD_NONBLOCK);
	pollfds[FD_SIGNAL].events = POLLIN;
}

/* ---- Main ---- */

int
main(int argc, char *argv[])
{
	/* Initialize palette with defaults */
	memcpy(&panel.palette_slots, &default_palette_slots,
		sizeof(panel.palette_slots));
	memcpy(&panel.palette, &default_palette, sizeof(panel.palette));
	memcpy(&panel.fp_button_palette, &default_palette, sizeof(panel.fp_button_palette));
	panel.fp_variant = 8;
	recalculate_panel_palettes();

	/* Initialize poll fds to invalid */
	for (int i = 0; i < NR_FDS; i++) {
		pollfds[i].fd = -1;
	}
	nscde_runtime_subscription_init(&panel.runtime_subscription);

	setup_paths();

	/* Initial state read */
	sync_state_from_best_source();
	if (setup_runtime_subscription()) {
		handle_runtime_subscription();
	}

	/* Connect to Wayland */
	panel.display = wl_display_connect(NULL);
	if (!panel.display) {
		fprintf(stderr, "nscde_paneld: unable to connect to Wayland display\n");
		return 1;
	}

	struct wl_registry *registry = wl_display_get_registry(panel.display);
	wl_registry_add_listener(registry, &registry_listener, NULL);
	if (wl_display_roundtrip(panel.display) < 0) {
		fprintf(stderr, "nscde_paneld: failed initial roundtrip\n");
		return 1;
	}

	if (!panel.compositor || !panel.layer_shell || !panel.shm) {
		fprintf(stderr, "nscde_paneld: missing required Wayland globals\n");
		return 1;
	}

	/* Create surface */
	panel.surface = wl_compositor_create_surface(panel.compositor);
	if (!panel.surface) {
		fprintf(stderr, "nscde_paneld: failed to create surface\n");
		return 1;
	}

	/* Create layer surface: top layer, edge-anchored, content width */
	panel.layer_surface = zwlr_layer_shell_v1_get_layer_surface(
		panel.layer_shell, panel.surface, NULL,
		ZWLR_LAYER_SHELL_V1_LAYER_TOP,
		"nscde-panel");
	if (!panel.layer_surface) {
		fprintf(stderr, "nscde_paneld: failed to create layer surface\n");
		return 1;
	}

	zwlr_layer_surface_v1_add_listener(panel.layer_surface,
		&layer_surface_listener, NULL);

	/* Anchor to the configured edge (default: bottom for CDE parity).
	 * With both left+right anchors and an explicit width, layer-shell centers
	 * the panel horizontally instead of stretching it across the full output. */
	uint32_t edge_anchor = ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT |
		ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;
	if (strcmp(panel.layout_edge, "bottom") == 0) {
		edge_anchor |= ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM;
	} else {
		edge_anchor |= ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP;
	}
	zwlr_layer_surface_v1_set_anchor(panel.layer_surface, edge_anchor);
	zwlr_layer_surface_v1_set_exclusive_zone(panel.layer_surface,
		panel.layout_height + panel.layout_border_width * 2);
	recompute_panel_dimensions();
	zwlr_layer_surface_v1_set_size(panel.layer_surface, panel.width,
		panel.height);

	/* Initial commit to trigger configure */
	wl_surface_commit(panel.surface);
	wl_display_roundtrip(panel.display);

	wl_registry_destroy(registry);

	/* Set up poll fds */
	pollfds[FD_WAYLAND].fd = wl_display_get_fd(panel.display);
	pollfds[FD_WAYLAND].events = POLLIN;
	setup_inotify();
	setup_watchdog_timer();
	setup_signals();

	/* Initial render */
	refresh_applet_state();
	render_and_commit();

	/* Event loop */
	while (panel.running) {
		while (wl_display_prepare_read(panel.display) != 0) {
			wl_display_dispatch_pending(panel.display);
		}

		errno = 0;
		if (wl_display_flush(panel.display) == -1 && errno != EAGAIN) {
			break;
		}

		int ret = poll(pollfds, NR_FDS, -1);
		if (ret < 0) {
			if (errno == EINTR) {
				wl_display_cancel_read(panel.display);
				continue;
			}
			break;
		}

		if (pollfds[FD_WAYLAND].revents & POLLIN) {
			wl_display_read_events(panel.display);
		} else {
			wl_display_cancel_read(panel.display);
		}

		if (pollfds[FD_RUNTIME].fd >= 0 &&
			(pollfds[FD_RUNTIME].revents &
			(POLLIN | POLLERR | POLLHUP | POLLNVAL))) {
			handle_runtime_subscription();
		}

		if (pollfds[FD_INOTIFY].revents & POLLIN) {
			drain_inotify();
			if (!panel.runtime_active) {
				parse_all_state_files();
			}
		}

		if (pollfds[FD_TIMER].revents & POLLIN) {
			uint64_t exp;
			ssize_t n = read(pollfds[FD_TIMER].fd, &exp, sizeof(exp));
			(void)n;
			refresh_applet_state();
			if (!panel.runtime_active) {
				refresh_state_transport();
			}
		}

		if (pollfds[FD_SIGNAL].revents & POLLIN) {
			break;
		}

		wl_display_dispatch_pending(panel.display);
	}

	/* Cleanup */
	close_subpanel();
	if (panel.layer_surface) {
		zwlr_layer_surface_v1_destroy(panel.layer_surface);
	}
	if (panel.surface) {
		wl_surface_destroy(panel.surface);
	}
	if (panel.layer_shell) {
		zwlr_layer_shell_v1_destroy(panel.layer_shell);
	}
	destroy_buffer(&panel.buffers[0]);
	destroy_buffer(&panel.buffers[1]);
	if (panel.compositor) {
		wl_compositor_destroy(panel.compositor);
	}
	if (panel.shm) {
		wl_shm_destroy(panel.shm);
	}
	if (panel_pointer) {
		wl_pointer_destroy(panel_pointer);
	}
	teardown_runtime_subscription();
	nscde_pixel_icon_destroy(&panel.pixel_icons);
	if (panel.display) {
		wl_display_disconnect(panel.display);
	}

	if (pollfds[FD_TIMER].fd >= 0) {
		close(pollfds[FD_TIMER].fd);
	}
	if (pollfds[FD_INOTIFY].fd >= 0) {
		close(pollfds[FD_INOTIFY].fd);
	}
	if (pollfds[FD_SIGNAL].fd >= 0) {
		close(pollfds[FD_SIGNAL].fd);
	}

	return 0;
}
