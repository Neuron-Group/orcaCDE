#include "panel-layout-contract.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define STATE_LINE_LEN 1024

static bool
parse_int_range(const char *value, int min, int max, int *dest)
{
	int parsed = atoi(value);

	if (parsed < min || parsed > max) {
		return false;
	}

	*dest = parsed;
	return true;
}

static void
copy_text(char *dest, size_t dest_size, const char *value)
{
	strncpy(dest, value, dest_size - 1);
	dest[dest_size - 1] = '\0';
}

bool
nscde_panel_layout_contract_parse_file(const char *path,
	struct nscde_panel_layout_contract *layout)
{
	FILE *f = fopen(path, "r");
	if (!f) {
		return false;
	}

	char line[STATE_LINE_LEN];
	while (fgets(line, sizeof(line), f)) {
		size_t len = strlen(line);
		while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r')) {
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

		if (strcmp(key, "NSCDE_PANEL_HEIGHT") == 0) {
			parse_int_range(val, 1, 511, &layout->height);
		} else if (strcmp(key, "NSCDE_PANEL_BORDER_WIDTH") == 0) {
			parse_int_range(val, 0, 31, &layout->border_width);
		} else if (strcmp(key, "NSCDE_PANEL_EDGE") == 0) {
			copy_text(layout->edge, sizeof(layout->edge), val);
		} else if (strcmp(key, "NSCDE_PANEL_MARGIN") == 0) {
			parse_int_range(val, 0, 255, &layout->margin);
		} else if (strcmp(key, "NSCDE_PANEL_WORKSPACE_MIN_BUTTON_WIDTH") == 0) {
			parse_int_range(val, 1, 511, &layout->button_min_width);
		} else if (strcmp(key, "NSCDE_PANEL_WORKSPACE_BUTTON_PADDING_X") == 0) {
			parse_int_range(val, 0, 127, &layout->button_padding);
		} else if (strcmp(key, "NSCDE_PANEL_WORKSPACE_BUTTON_GAP") == 0) {
			parse_int_range(val, 0, 63, &layout->button_gap);
		} else if (strcmp(key, "NSCDE_PANEL_WORKSPACE_RECESS_HEIGHT") == 0) {
			parse_int_range(val, 1, 255, &layout->ws_recess_height);
		} else if (strcmp(key, "NSCDE_PANEL_BEVEL_WIDTH") == 0) {
			parse_int_range(val, 0, 15, &layout->bevel_width);
		} else if (strcmp(key, "NSCDE_PANEL_FONT") == 0) {
			copy_text(layout->font, sizeof(layout->font), val);
		} else if (strcmp(key, "NSCDE_PANEL_RIGHT_AREA_WIDTH") == 0) {
			parse_int_range(val, 0, 1023, &layout->right_area_width);
		} else if (strcmp(key, "NSCDE_PANEL_LEFT_MODULES") == 0) {
			copy_text(layout->left_modules, sizeof(layout->left_modules), val);
		} else if (strcmp(key, "NSCDE_PANEL_LAUNCHER_UNIT_WIDTH") == 0) {
			parse_int_range(val, 1, 255, &layout->launcher_unit_width);
		} else if (strcmp(key, "NSCDE_PANEL_LAUNCHER_ICON_SIZE") == 0) {
			parse_int_range(val, 1, 127, &layout->launcher_icon_size);
		} else if (strcmp(key, "NSCDE_PANEL_LAUNCHER_GAP") == 0) {
			parse_int_range(val, 0, 63, &layout->launcher_gap);
		} else if (strcmp(key, "NSCDE_PANEL_RIGHT_MODULES") == 0) {
			copy_text(layout->right_modules, sizeof(layout->right_modules), val);
		} else if (strcmp(key, "NSCDE_PANEL_APPLET_UNIT_WIDTH") == 0) {
			parse_int_range(val, 1, 127, &layout->applet_unit_width);
		} else if (strcmp(key, "NSCDE_PANEL_SUBPANEL_ENTRY_HEIGHT") == 0) {
			parse_int_range(val, 1, 127, &layout->subpanel_entry_height);
		} else if (strcmp(key, "NSCDE_PANEL_SUBPANEL_ICON_SIZE") == 0) {
			parse_int_range(val, 1, 127, &layout->subpanel_icon_size);
		} else if (strcmp(key, "NSCDE_PANEL_SUBPANEL_TITLE_HEIGHT") == 0) {
			parse_int_range(val, 1, 127, &layout->subpanel_title_height);
		} else if (strcmp(key, "NSCDE_PANEL_SUBPANEL_PADDING") == 0) {
			parse_int_range(val, 0, 63, &layout->subpanel_padding);
		} else if (strcmp(key, "NSCDE_PANEL_LEFT_HANDLE_WIDTH") == 0) {
			parse_int_range(val, 1, 127, &layout->left_handle_width);
		} else if (strcmp(key, "NSCDE_PANEL_RIGHT_HANDLE_WIDTH") == 0) {
			parse_int_range(val, 1, 127, &layout->right_handle_width);
		} else if (strcmp(key, "NSCDE_PANEL_TRIGGER_HEIGHT") == 0) {
			parse_int_range(val, 1, 127, &layout->trigger_height);
		} else if (strcmp(key, "NSCDE_PANEL_BODY_HEIGHT") == 0) {
			parse_int_range(val, 1, 255, &layout->body_height);
		} else if (strcmp(key, "NSCDE_PANEL_BOTTOM_STRIP_HEIGHT") == 0) {
			parse_int_range(val, 0, 31, &layout->bottom_strip_height);
		} else if (strcmp(key, "NSCDE_PANEL_SECTION_SEPARATOR_WIDTH") == 0) {
			parse_int_range(val, 0, 15, &layout->section_separator_width);
		} else if (strcmp(key, "NSCDE_PANEL_RIGHT_APPLET_GAP") == 0) {
			parse_int_range(val, 0, 31, &layout->applet_gap);
		} else if (strcmp(key, "NSCDE_DESK_COUNT") == 0) {
			parse_int_range(val, 0, 32, &layout->desk_count);
		} else if (strcmp(key, "NSCDE_PANEL_WSM_WIDTH") == 0) {
			parse_int_range(val, 1, 2047, &layout->wsm_width);
		} else if (strcmp(key, "NSCDE_PANEL_WSM_LOCK_WIDTH") == 0) {
			parse_int_range(val, 1, 63, &layout->wsm_lock_width);
		} else if (strcmp(key, "NSCDE_PANEL_WSM_EXIT_WIDTH") == 0) {
			parse_int_range(val, 1, 63, &layout->wsm_exit_width);
		} else if (strcmp(key, "NSCDE_PANEL_WSM_BUTTONS_WIDTH") == 0) {
			parse_int_range(val, 0, 2047, &layout->wsm_buttons_width);
		} else if (strcmp(key, "NSCDE_PANEL_LEFT_LAUNCHER_COUNT") == 0) {
			parse_int_range(val, 0, 15, &layout->left_launcher_count);
		} else if (strcmp(key, "NSCDE_PANEL_RIGHT_LAUNCHER_COUNT") == 0) {
			parse_int_range(val, 0, 15, &layout->right_launcher_count);
		} else if (strcmp(key, "NSCDE_PANEL_LEFT_BANK_WIDTH") == 0) {
			parse_int_range(val, 0, 2047, &layout->left_bank_width);
		} else if (strcmp(key, "NSCDE_PANEL_RIGHT_BANK_WIDTH") == 0) {
			parse_int_range(val, 0, 2047, &layout->right_bank_width);
		} else if (strcmp(key, "NSCDE_PANEL_CENTER_SECTION_X") == 0) {
			parse_int_range(val, 0, 4095, &layout->center_section_x);
		} else if (strcmp(key, "NSCDE_PANEL_CENTER_SECTION_WIDTH") == 0) {
			parse_int_range(val, 1, 2047, &layout->center_section_width);
		} else if (strcmp(key, "NSCDE_PANEL_WSM_INNER_PAD") == 0) {
			parse_int_range(val, 0, 255, &layout->wsm_inner_pad);
		} else if (strcmp(key, "NSCDE_PANEL_WSM_SIDE_WIDTH") == 0) {
			parse_int_range(val, 1, 511, &layout->wsm_side_width);
		} else if (strcmp(key, "NSCDE_PANEL_WSM_UTILITY_WIDTH") == 0) {
			parse_int_range(val, 1, 511, &layout->wsm_utility_width);
		} else if (strcmp(key, "NSCDE_PANEL_WSM_SECTION_GAP") == 0) {
			parse_int_range(val, 0, 255, &layout->wsm_section_gap);
		} else if (strcmp(key, "NSCDE_PANEL_WSM_GRID_VPAD") == 0) {
			parse_int_range(val, 0, 255, &layout->wsm_grid_vpad);
		} else if (strcmp(key, "NSCDE_PANEL_WSM_LOCK_HEIGHT") == 0) {
			parse_int_range(val, 1, 511, &layout->wsm_lock_height);
		} else if (strcmp(key, "NSCDE_PANEL_WSM_LOAD_INSET_TOP") == 0) {
			parse_int_range(val, 0, 255, &layout->wsm_load_inset_top);
		} else if (strcmp(key, "NSCDE_PANEL_WSM_LOAD_INSET_SIDE") == 0) {
			parse_int_range(val, 0, 255, &layout->wsm_load_inset_side);
		} else if (strcmp(key, "NSCDE_PANEL_WSM_LOAD_HEIGHT") == 0) {
			parse_int_range(val, 1, 511, &layout->wsm_load_height);
		} else if (strcmp(key, "NSCDE_PANEL_WSM_EXIT_HEIGHT") == 0) {
			parse_int_range(val, 1, 511, &layout->wsm_exit_height);
		} else if (strcmp(key, "NSCDE_PANEL_WSM_EXIT_INSET_BOTTOM") == 0) {
			parse_int_range(val, 0, 255, &layout->wsm_exit_inset_bottom);
		} else if (strcmp(key, "NSCDE_PANEL_WSM_UTILITY_INSET_SIDE") == 0) {
			parse_int_range(val, 0, 255, &layout->wsm_utility_inset_side);
		} else if (strcmp(key, "NSCDE_PANEL_SCALE") == 0) {
			parse_int_range(val, 1, 400, &layout->scale);
		} else if (strcmp(key, "NSCDE_PANEL_LAYOUT_VERSION") == 0) {
			parse_int_range(val, 0, 127, &layout->version);
		} else if (strcmp(key, "NSCDE_PANEL_LAYOUT_SOURCE") == 0) {
			copy_text(layout->source, sizeof(layout->source), val);
		} else if (strcmp(key, "NSCDE_PANEL_WS_FONT") == 0) {
			copy_text(layout->ws_font, sizeof(layout->ws_font), val);
		} else if (strcmp(key, "NSCDE_PANEL_APPLET_DATE_FONT") == 0) {
			copy_text(layout->applet_date_font,
				sizeof(layout->applet_date_font), val);
		} else if (strcmp(key, "NSCDE_PANEL_APPLET_MAIL_FONT") == 0) {
			copy_text(layout->applet_mail_font,
				sizeof(layout->applet_mail_font), val);
		} else if (strcmp(key, "NSCDE_PANEL_APPLET_CLOCK_SIZE") == 0) {
			parse_int_range(val, 1, 255, &layout->applet_clock_size);
		} else if (strcmp(key, "NSCDE_PANEL_APPLET_DATE_SIZE") == 0) {
			parse_int_range(val, 1, 255, &layout->applet_date_size);
		} else if (strcmp(key, "NSCDE_PANEL_APPLET_MAIL_SIZE") == 0) {
			parse_int_range(val, 1, 255, &layout->applet_mail_size);
		} else if (strcmp(key, "NSCDE_PANEL_APPLET_LOAD_WIDTH") == 0) {
			parse_int_range(val, 1, 255, &layout->applet_load_width);
		} else if (strcmp(key, "NSCDE_PANEL_APPLET_LOAD_HEIGHT") == 0) {
			parse_int_range(val, 1, 255, &layout->applet_load_height);
		} else if (strcmp(key, "NSCDE_PANEL_PROFILE") == 0) {
			copy_text(layout->profile, sizeof(layout->profile), val);
		}
	}

	fclose(f);
	return true;
}
