// QtWidgets gallery: every control the style draws, in the states a
// screenshot can show. Wayland won't open a menu without real input, so with
// GALLERY_GRAB=<dir> (run it with QT_QPA_PLATFORM=offscreen) it renders the
// window, a menu and a combo list itself into <dir>/{window,menu,combo}.png.
#include <QtWidgets>

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    const QString popup = argc > 1 ? QString::fromLocal8Bit(argv[1]) : QString();

    QMainWindow win;
    win.setWindowTitle(QStringLiteral("Widgets gallery"));
    auto *menu = win.menuBar()->addMenu(QStringLiteral("&File"));
    menu->addAction(QIcon::fromTheme(QStringLiteral("document-new")), QStringLiteral("New"), QKeySequence::New);
    auto *open = menu->addAction(QIcon::fromTheme(QStringLiteral("document-open")), QStringLiteral("Open…"), QKeySequence::Open);
    auto *recent = menu->addMenu(QIcon::fromTheme(QStringLiteral("document-open-recent")), QStringLiteral("Open Recent"));
    recent->addAction(QStringLiteral("notes.md"));
    menu->addSeparator();
    auto *wrap = menu->addAction(QStringLiteral("Word Wrap"));
    wrap->setCheckable(true);
    wrap->setChecked(true);
    menu->addAction(QIcon::fromTheme(QStringLiteral("edit-delete")), QStringLiteral("Move to Trash"), QKeySequence::Delete);
    menu->addAction(QStringLiteral("Disabled entry"))->setEnabled(false);
    win.menuBar()->addMenu(QStringLiteral("&Edit"));
    win.menuBar()->addMenu(QStringLiteral("&View"));

    auto *tb = win.addToolBar(QStringLiteral("Main"));
    tb->setToolButtonStyle(Qt::ToolButtonTextBesideIcon);
    tb->addAction(QIcon::fromTheme(QStringLiteral("go-previous")), QStringLiteral("Back"));
    auto *split = tb->addAction(QIcon::fromTheme(QStringLiteral("view-split-left-right")), QStringLiteral("Split"));
    split->setCheckable(true);
    split->setChecked(true);
    tb->addAction(QIcon::fromTheme(QStringLiteral("edit-find")), QStringLiteral("Find"));

    auto *central = new QWidget;
    auto *grid = new QGridLayout(central);

    auto *buttons = new QGroupBox(QStringLiteral("Buttons"));
    auto *bl = new QVBoxLayout(buttons);
    auto *def = new QPushButton(QStringLiteral("Default"));
    def->setDefault(true);
    bl->addWidget(def);
    bl->addWidget(new QPushButton(QIcon::fromTheme(QStringLiteral("document-save")), QStringLiteral("With icon")));
    auto *off = new QPushButton(QStringLiteral("Disabled"));
    off->setEnabled(false);
    bl->addWidget(off);
    auto *flat = new QPushButton(QStringLiteral("Flat"));
    flat->setFlat(true);
    bl->addWidget(flat);
    auto *tog = new QPushButton(QStringLiteral("Toggled"));
    tog->setCheckable(true);
    tog->setChecked(true);
    bl->addWidget(tog);
    grid->addWidget(buttons, 0, 0);

    auto *checks = new QGroupBox(QStringLiteral("Choices"));
    auto *cl = new QVBoxLayout(checks);
    auto *c1 = new QCheckBox(QStringLiteral("Checked"));
    c1->setChecked(true);
    cl->addWidget(c1);
    cl->addWidget(new QCheckBox(QStringLiteral("Unchecked")));
    auto *c3 = new QCheckBox(QStringLiteral("Partial"));
    c3->setTristate(true);
    c3->setCheckState(Qt::PartiallyChecked);
    cl->addWidget(c3);
    auto *r1 = new QRadioButton(QStringLiteral("Radio on"));
    r1->setChecked(true);
    cl->addWidget(r1);
    cl->addWidget(new QRadioButton(QStringLiteral("Radio off")));
    auto *coff = new QCheckBox(QStringLiteral("Disabled"));
    coff->setEnabled(false);
    cl->addWidget(coff);
    grid->addWidget(checks, 0, 1);

    auto *inputs = new QGroupBox(QStringLiteral("Inputs"));
    auto *il = new QFormLayout(inputs);
    auto *focused = new QLineEdit(QStringLiteral("Focused"));
    il->addRow(QStringLiteral("Name"), focused);
    auto *ph = new QLineEdit;
    ph->setPlaceholderText(QStringLiteral("Placeholder"));
    il->addRow(QStringLiteral("Search"), ph);
    auto *combo = new QComboBox;
    combo->addItems({QStringLiteral("Nocturne"), QStringLiteral("Graphite"), QStringLiteral("Abyss")});
    il->addRow(QStringLiteral("Combo"), combo);
    il->addRow(QStringLiteral("Spin"), new QSpinBox);
    auto *slider = new QSlider(Qt::Horizontal);
    slider->setValue(60);
    il->addRow(QStringLiteral("Slider"), slider);
    auto *prog = new QProgressBar;
    prog->setValue(64);
    il->addRow(QStringLiteral("Progress"), prog);
    grid->addWidget(inputs, 0, 2);

    auto *tabs = new QTabWidget;
    auto *tree = new QTreeWidget;
    tree->setHeaderLabels({QStringLiteral("Name"), QStringLiteral("Size")});
    for (int i = 0; i < 30; ++i) {
        auto *it = new QTreeWidgetItem(tree, {QStringLiteral("Item %1").arg(i + 1), QStringLiteral("%1 KiB").arg(i * 7 + 3)});
        it->setIcon(0, QIcon::fromTheme(i % 4 ? QStringLiteral("text-x-generic") : QStringLiteral("folder")));
    }
    tree->setCurrentItem(tree->topLevelItem(2));
    tabs->addTab(tree, QStringLiteral("List"));
    tabs->addTab(new QTextEdit(QStringLiteral("Text area")), QStringLiteral("Text"));
    tabs->addTab(new QWidget, QStringLiteral("Third"));
    grid->addWidget(tabs, 1, 0, 1, 3);

    win.setCentralWidget(central);
    win.statusBar()->showMessage(QStringLiteral("30 items"));
    win.resize(900, 620);
    win.show();
    focused->setFocus(Qt::TabFocusReason);

    const QString grab = qEnvironmentVariable("GALLERY_GRAB");
    if (!grab.isEmpty()) {
        QTimer::singleShot(800, [&] {
            win.grab().save(grab + QStringLiteral("/window.png"));
            menu->popup(QPoint(10, 30));
            menu->setActiveAction(open); // stands in for the pointer hovering it
        });
        QTimer::singleShot(1400, [&] {
            menu->grab().save(grab + QStringLiteral("/menu.png"));
            menu->hide();
            combo->showPopup();
        });
        QTimer::singleShot(2000, [&] {
            combo->view()->window()->grab().save(grab + QStringLiteral("/combo.png"));
            app.quit();
        });
    } else if (popup == QLatin1String("tooltip")) {
        QTimer::singleShot(2500, [&] {
            QToolTip::showText(win.mapToGlobal(QPoint(120, 80)), QStringLiteral("Split the view in two"), &win);
        });
    }
    return app.exec();
}
