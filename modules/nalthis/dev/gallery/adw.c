// libadwaita gallery: which of our colors a GTK 4 / libadwaita app picks up
// from nalthis.css, for dev/test.sh (gtk.sh builds it).
#include <adwaita.h>

static void activate(GtkApplication *app) {
	GtkWidget *win = adw_application_window_new(app);
	gtk_window_set_default_size(GTK_WINDOW(win), 640, 520);
	GtkWidget *view = adw_toolbar_view_new();
	GtkWidget *header = adw_header_bar_new();
	adw_header_bar_set_title_widget(ADW_HEADER_BAR(header), adw_window_title_new("libadwaita", "GTK 4"));
	adw_toolbar_view_add_top_bar(ADW_TOOLBAR_VIEW(view), header);

	GtkWidget *page = adw_preferences_page_new();
	GtkWidget *group = adw_preferences_group_new();
	adw_preferences_group_set_title(ADW_PREFERENCES_GROUP(group), "Group");
	GtkWidget *sw = adw_switch_row_new();
	adw_preferences_row_set_title(ADW_PREFERENCES_ROW(sw), "Switch row");
	adw_switch_row_set_active(ADW_SWITCH_ROW(sw), TRUE);
	adw_preferences_group_add(ADW_PREFERENCES_GROUP(group), sw);
	GtkWidget *entry = adw_entry_row_new();
	adw_preferences_row_set_title(ADW_PREFERENCES_ROW(entry), "Entry row");
	adw_preferences_group_add(ADW_PREFERENCES_GROUP(group), entry);
	GtkWidget *check = adw_action_row_new();
	adw_preferences_row_set_title(ADW_PREFERENCES_ROW(check), "Check");
	GtkWidget *cb = gtk_check_button_new();
	gtk_check_button_set_active(GTK_CHECK_BUTTON(cb), TRUE);
	adw_action_row_add_suffix(ADW_ACTION_ROW(check), cb);
	adw_preferences_group_add(ADW_PREFERENCES_GROUP(group), check);
	adw_preferences_page_add(ADW_PREFERENCES_PAGE(page), ADW_PREFERENCES_GROUP(group));

	GtkWidget *group2 = adw_preferences_group_new();
	GtkWidget *buttons = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
	GtkWidget *b1 = gtk_button_new_with_label("Suggested");
	gtk_widget_add_css_class(b1, "suggested-action");
	GtkWidget *b2 = gtk_button_new_with_label("Destructive");
	gtk_widget_add_css_class(b2, "destructive-action");
	gtk_box_append(GTK_BOX(buttons), gtk_button_new_with_label("Button"));
	gtk_box_append(GTK_BOX(buttons), b1);
	gtk_box_append(GTK_BOX(buttons), b2);
	GtkWidget *scale = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, 0, 100, 1);
	gtk_range_set_value(GTK_RANGE(scale), 60);
	gtk_widget_set_hexpand(scale, TRUE);
	gtk_box_append(GTK_BOX(buttons), scale);
	adw_preferences_group_add(ADW_PREFERENCES_GROUP(group2), buttons);
	GtkWidget *list = gtk_list_box_new();
	gtk_widget_add_css_class(list, "boxed-list");
	for (int i = 0; i < 3; i++) {
		GtkWidget *r = adw_action_row_new();
		adw_preferences_row_set_title(ADW_PREFERENCES_ROW(r), i == 1 ? "Selected row" : "Row");
		gtk_list_box_append(GTK_LIST_BOX(list), r);
	}
	gtk_list_box_select_row(GTK_LIST_BOX(list), gtk_list_box_get_row_at_index(GTK_LIST_BOX(list), 1));
	adw_preferences_group_add(ADW_PREFERENCES_GROUP(group2), list);
	adw_preferences_page_add(ADW_PREFERENCES_PAGE(page), ADW_PREFERENCES_GROUP(group2));

	adw_toolbar_view_set_content(ADW_TOOLBAR_VIEW(view), page);
	adw_application_window_set_content(ADW_APPLICATION_WINDOW(win), view);
	gtk_window_present(GTK_WINDOW(win));
}

int main(int argc, char **argv) {
	AdwApplication *app = adw_application_new("org.nalthis.AdwGallery", G_APPLICATION_NON_UNIQUE);
	g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
	return g_application_run(G_APPLICATION(app), argc, argv);
}
