#ifndef NSCDE_PANEL_LAYOUT_CONTRACT_H
#define NSCDE_PANEL_LAYOUT_CONTRACT_H

#include <stdbool.h>

#define NSCDE_PANEL_LAYOUT_EDGE_LEN 32
#define NSCDE_PANEL_LAYOUT_TEXT_LEN 256

struct nscde_panel_layout_contract {
	int height;
	int border_width;
	char edge[NSCDE_PANEL_LAYOUT_EDGE_LEN];
	int button_min_width;
	int button_padding;
	int button_gap;
	int margin;
	int bevel_width;
	int right_area_width;
	int ws_recess_height;
	int launcher_unit_width;
	int launcher_icon_size;
	int launcher_gap;
	char font[NSCDE_PANEL_LAYOUT_TEXT_LEN];
	char left_modules[NSCDE_PANEL_LAYOUT_TEXT_LEN];
	char right_modules[NSCDE_PANEL_LAYOUT_TEXT_LEN];
	int applet_unit_width;
	int left_handle_width;
	int right_handle_width;
	int trigger_height;
	int body_height;
	int bottom_strip_height;
	int section_separator_width;
	int applet_gap;
	int desk_count;
	int wsm_width;
	int wsm_lock_width;
	int wsm_exit_width;
	int wsm_buttons_width;
	int left_launcher_count;
	int right_launcher_count;
	int left_bank_width;
	int right_bank_width;
	int center_section_x;
	int center_section_width;
	int wsm_inner_pad;
	int wsm_side_width;
	int wsm_utility_width;
	int wsm_section_gap;
	int wsm_grid_vpad;
	int wsm_lock_height;
	int wsm_load_inset_top;
	int wsm_load_inset_side;
	int wsm_load_height;
	int wsm_exit_height;
	int wsm_exit_inset_bottom;
	int wsm_utility_inset_side;
	int scale;
	int version;
	char source[64];
	char ws_font[NSCDE_PANEL_LAYOUT_TEXT_LEN];
	char applet_date_font[NSCDE_PANEL_LAYOUT_TEXT_LEN];
	char applet_mail_font[NSCDE_PANEL_LAYOUT_TEXT_LEN];
	int applet_clock_size;
	int applet_date_size;
	int applet_mail_size;
	int applet_load_width;
	int applet_load_height;
	int subpanel_entry_height;
	int subpanel_icon_size;
	int subpanel_title_height;
	int subpanel_padding;
	char profile[NSCDE_PANEL_LAYOUT_TEXT_LEN];
};

#define NSCDE_PANEL_LAYOUT_CONTRACT_DEFAULTS { \
	.height = 79, \
	.border_width = 4, \
	.edge = "bottom", \
	.button_min_width = 84, \
	.button_padding = 10, \
	.button_gap = 6, \
	.margin = 0, \
	.bevel_width = 1, \
	.right_area_width = 200, \
	.ws_recess_height = 32, \
	.launcher_unit_width = 63, \
	.launcher_icon_size = 48, \
	.launcher_gap = 0, \
	.font = "DejaVu Serif 9", \
	.left_modules = "clock,date,home,term,mail", \
	.right_modules = "print,style,apps,multimedia,help", \
	.applet_unit_width = 50, \
	.left_handle_width = 21, \
	.right_handle_width = 21, \
	.trigger_height = 16, \
	.body_height = 62, \
	.bottom_strip_height = 1, \
	.section_separator_width = 1, \
	.applet_gap = 4, \
	.desk_count = 4, \
	.wsm_width = 343, \
	.wsm_lock_width = 2, \
	.wsm_exit_width = 2, \
	.wsm_buttons_width = 0, \
	.left_launcher_count = 5, \
	.right_launcher_count = 5, \
	.left_bank_width = 311, \
	.right_bank_width = 311, \
	.center_section_x = 332, \
	.center_section_width = 343, \
	.wsm_inner_pad = 5, \
	.wsm_side_width = 43, \
	.wsm_utility_width = 43, \
	.wsm_section_gap = 6, \
	.wsm_grid_vpad = 3, \
	.wsm_lock_height = 34, \
	.wsm_load_inset_top = 8, \
	.wsm_load_inset_side = 5, \
	.wsm_load_height = 14, \
	.wsm_exit_height = 30, \
	.wsm_exit_inset_bottom = 4, \
	.wsm_utility_inset_side = 5, \
	.scale = 100, \
	.version = 0, \
	.source = "shell-runtime", \
	.ws_font = "DejaVu Serif 10", \
	.applet_date_font = "DejaVu Sans Bold 12", \
	.applet_mail_font = "DejaVu Sans 10", \
	.applet_clock_size = 56, \
	.applet_date_size = 56, \
	.applet_mail_size = 56, \
	.applet_load_width = 36, \
	.applet_load_height = 34, \
	.subpanel_entry_height = 32, \
	.subpanel_icon_size = 32, \
	.subpanel_title_height = 20, \
	.subpanel_padding = 4, \
	.profile = "reference", \
}

bool
nscde_panel_layout_contract_parse_contents(const char *contents,
	struct nscde_panel_layout_contract *layout);

bool
nscde_panel_layout_contract_parse_file(const char *path,
	struct nscde_panel_layout_contract *layout);

#endif
