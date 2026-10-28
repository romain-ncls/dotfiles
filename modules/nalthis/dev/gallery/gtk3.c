// GTK 3 gallery: the controls nalthis.css restyles, in one window, for
// dev/test.sh (gtk.sh builds it).
#include <gtk/gtk.h>

static GtkWidget *row(GtkWidget *box) {
	GtkWidget *r = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
	gtk_box_pack_start(GTK_BOX(box), r, FALSE, FALSE, 0);
	return r;
}

static gboolean show_popover(gpointer p) {
	gtk_popover_popup(GTK_POPOVER(p));
	return G_SOURCE_REMOVE;
}

int main(int argc, char **argv) {
	gtk_init(&argc, &argv);
	GtkWidget *win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
	gtk_window_set_default_size(GTK_WINDOW(win), 640, 520);
	GtkWidget *header = gtk_header_bar_new();
	gtk_header_bar_set_title(GTK_HEADER_BAR(header), "GTK 3");
	gtk_header_bar_set_show_close_button(GTK_HEADER_BAR(header), TRUE);
	GtkWidget *menu = gtk_menu_button_new();
	gtk_header_bar_pack_end(GTK_HEADER_BAR(header), menu);
	gtk_window_set_titlebar(GTK_WINDOW(win), header);

	GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
	gtk_container_set_border_width(GTK_CONTAINER(box), 14);
	gtk_container_add(GTK_CONTAINER(win), box);

	GtkWidget *r = row(box);
	gtk_box_pack_start(GTK_BOX(r), gtk_button_new_with_label("Button"), FALSE, FALSE, 0);
	GtkWidget *ok = gtk_button_new_with_label("Suggested");
	gtk_style_context_add_class(gtk_widget_get_style_context(ok), "suggested-action");
	gtk_box_pack_start(GTK_BOX(r), ok, FALSE, FALSE, 0);
	GtkWidget *linked = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
	gtk_style_context_add_class(gtk_widget_get_style_context(linked), "linked");
	for (const char *l = "ABC"; *l; l++) {
		char s[2] = {*l, 0};
		gtk_box_pack_start(GTK_BOX(linked), gtk_button_new_with_label(s), FALSE, FALSE, 0);
	}
	gtk_box_pack_start(GTK_BOX(r), linked, FALSE, FALSE, 0);
	GtkWidget *combo = gtk_combo_box_text_new();
	gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(combo), "Combo box");
	gtk_combo_box_set_active(GTK_COMBO_BOX(combo), 0);
	gtk_box_pack_start(GTK_BOX(r), combo, FALSE, FALSE, 0);

	r = row(box);
	GtkWidget *entry = gtk_entry_new();
	gtk_entry_set_placeholder_text(GTK_ENTRY(entry), "Entry");
	gtk_box_pack_start(GTK_BOX(r), entry, TRUE, TRUE, 0);
	gtk_box_pack_start(GTK_BOX(r), gtk_spin_button_new_with_range(0, 100, 1), FALSE, FALSE, 0);

	r = row(box);
	GtkWidget *c1 = gtk_check_button_new_with_label("Checked");
	gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(c1), TRUE);
	gtk_box_pack_start(GTK_BOX(r), c1, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(r), gtk_check_button_new_with_label("Unchecked"), FALSE, FALSE, 0);
	GtkWidget *r1 = gtk_radio_button_new_with_label(NULL, "Radio");
	gtk_box_pack_start(GTK_BOX(r), r1, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(r), gtk_radio_button_new_with_label_from_widget(GTK_RADIO_BUTTON(r1), "Other"), FALSE, FALSE, 0);
	GtkWidget *sw = gtk_switch_new();
	gtk_switch_set_active(GTK_SWITCH(sw), TRUE);
	gtk_box_pack_start(GTK_BOX(r), sw, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(r), gtk_switch_new(), FALSE, FALSE, 0);

	r = row(box);
	GtkWidget *scale = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, 0, 100, 1);
	gtk_range_set_value(GTK_RANGE(scale), 60);
	gtk_scale_set_draw_value(GTK_SCALE(scale), FALSE);
	gtk_box_pack_start(GTK_BOX(r), scale, TRUE, TRUE, 0);
	GtkWidget *bar = gtk_progress_bar_new();
	gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(bar), 0.4);
	gtk_widget_set_valign(bar, GTK_ALIGN_CENTER);
	gtk_box_pack_start(GTK_BOX(r), bar, TRUE, TRUE, 0);

	GtkWidget *nb = gtk_notebook_new();
	GtkWidget *sc = gtk_scrolled_window_new(NULL, NULL);
	gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(sc), GTK_POLICY_NEVER, GTK_POLICY_ALWAYS);
	gtk_scrolled_window_set_overlay_scrolling(GTK_SCROLLED_WINDOW(sc), FALSE);
	GtkWidget *list = gtk_list_box_new();
	for (int i = 0; i < 30; i++) {
		char s[32];
		snprintf(s, sizeof s, "List row %d", i + 1);
		GtkWidget *l = gtk_label_new(s);
		gtk_widget_set_halign(l, GTK_ALIGN_START);
		gtk_widget_set_margin_start(l, 8);
		gtk_widget_set_margin_top(l, 4);
		gtk_widget_set_margin_bottom(l, 4);
		gtk_list_box_insert(GTK_LIST_BOX(list), l, -1);
	}
	gtk_list_box_select_row(GTK_LIST_BOX(list), gtk_list_box_get_row_at_index(GTK_LIST_BOX(list), 1));
	gtk_container_add(GTK_CONTAINER(sc), list);
	gtk_notebook_append_page(GTK_NOTEBOOK(nb), sc, gtk_label_new("List"));
	gtk_notebook_append_page(GTK_NOTEBOOK(nb), gtk_label_new(""), gtk_label_new("Other tab"));
	gtk_box_pack_start(GTK_BOX(box), nb, TRUE, TRUE, 0);

	GtkWidget *pop = gtk_popover_new(menu);
	GtkWidget *pbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
	gtk_container_set_border_width(GTK_CONTAINER(pbox), 8);
	gtk_box_pack_start(GTK_BOX(pbox), gtk_model_button_new(), FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(pbox), gtk_label_new("A popover"), FALSE, FALSE, 0);
	gtk_container_add(GTK_CONTAINER(pop), pbox);
	gtk_widget_show_all(pbox);
	gtk_menu_button_set_popover(GTK_MENU_BUTTON(menu), pop);

	g_signal_connect(win, "destroy", G_CALLBACK(gtk_main_quit), NULL);
	gtk_widget_show_all(win);
	g_timeout_add(1500, show_popover, pop);
	gtk_main();
	return 0;
}
