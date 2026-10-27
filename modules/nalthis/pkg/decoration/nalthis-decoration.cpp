// Nalthis window decoration: the title bar merges with the toolbar, 12 px
// corners all round (KWin rounds the bottom ones from setBorderRadius), and
// two kinds of buttons. The window controls on the right are full-height
// tiles, the close tile filling the corner; the buttons on the left are
// square ghost buttons like the toolbar's. Colors come from the color
// scheme, so the palette sliders recolor it live. Modelled on Breeze's
// decoration (kdecoration/ in plasma/breeze), much reduced.

#include <KDecoration3/DecoratedWindow>
#include <KDecoration3/Decoration>
#include <KDecoration3/DecorationButton>
#include <KDecoration3/DecorationButtonGroup>
#include <KDecoration3/DecorationSettings>
#include <KDecoration3/DecorationShadow>
#include <KDecoration3/ScaleHelpers>

#include <KColorScheme>
#include <KConfigGroup>
#include <KPluginFactory>
#include <KSharedConfig>

#include <QPainter>
#include <QPainterPath>
#include <QRegularExpression>

#include <cmath>

using KDecoration3::ColorGroup;
using KDecoration3::ColorRole;
using KDecoration3::DecorationButtonType;

namespace Nalthis
{

// Sizes in logical pixels, from the design page ("medium" buttons).
constexpr qreal TitleBarHeight = 36;
constexpr qreal CornerRadius = 12;
constexpr qreal TileWidth = 44;
constexpr qreal GhostSize = 24;
constexpr qreal GhostRadius = 6;
constexpr qreal GhostSpacing = 4;
constexpr qreal SidePadding = 6;
constexpr qreal GlyphSize = 16;
constexpr qreal ResizeBorder = 8;

class Decoration;

class Button : public KDecoration3::DecorationButton
{
    Q_OBJECT
public:
    Button(DecorationButtonType type, Decoration *decoration, QObject *parent);
    // KWin's decoration settings preview creates buttons through the plugin.
    Button(QObject *parent, const QVariantList &args);
    static KDecoration3::DecorationButton *create(DecorationButtonType type, KDecoration3::Decoration *decoration, QObject *parent);

    void paint(QPainter *painter, const QRectF &repaintArea) override;
    bool tile = false; // window control on the right, or ghost button

private:
    void paintGlyph(QPainter *painter, const QRectF &box, const QColor &color) const;
};

class Decoration : public KDecoration3::Decoration
{
    Q_OBJECT
public:
    Decoration(QObject *parent, const QVariantList &args)
        : KDecoration3::Decoration(parent, args)
    {
    }

    bool init() override;
    void paint(QPainter *painter, const QRectF &repaintArea) override;

    bool isFloating() const
    {
        // Maximized or tiled against a screen edge: square corners, as in
        // Windows; the radius only shows on floating windows.
        const auto w = window();
        return !w->isMaximized() && w->adjacentScreenEdges() == Qt::Edges();
    }
    qreal radius() const { return isFloating() ? KDecoration3::snapToPixelGrid(CornerRadius, window()->nextScale()) : 0; }
    QColor color(ColorRole role) const { return window()->color(window()->isActive() ? ColorGroup::Active : ColorGroup::Inactive, role); }
    QColor closeColor() const
    {
        // The scheme's red, deepened so a light glyph reads on it.
        return KColorScheme(QPalette::Active, KColorScheme::Window).foreground(KColorScheme::NegativeText).color().darker(135);
    }

private:
    void updateLayout();
    void updateShadow();
    // No title bar: KWin asked for a shadow only (apps drawing their own, like
    // Steam), or the window is in the "hide title bar" exceptions. The
    // corners stay rounded and the shadow stays.
    bool frameless() const { return style() == KDecoration3::Style::Shadow || m_hideTitleBar; }
    void readExceptions();

    KDecoration3::DecorationButtonGroup *m_left = nullptr;
    KDecoration3::DecorationButtonGroup *m_right = nullptr;
    bool m_hideTitleBar = false;
};

// ---------------------------------------------------------------------------

Button::Button(DecorationButtonType type, Decoration *decoration, QObject *parent)
    : KDecoration3::DecorationButton(type, decoration, parent)
{
    connect(this, &DecorationButton::hoveredChanged, this, [this] { update(); });
    connect(this, &DecorationButton::pressedChanged, this, [this] { update(); });
    connect(this, &DecorationButton::checkedChanged, this, [this] { update(); });
}

Button::Button(QObject *parent, const QVariantList &args)
    : Button(args.at(0).value<DecorationButtonType>(), args.at(1).value<Decoration *>(), parent)
{
    setGeometry(QRectF(0, 0, GhostSize, GhostSize));
}

KDecoration3::DecorationButton *Button::create(DecorationButtonType type, KDecoration3::Decoration *decoration, QObject *parent)
{
    auto d = qobject_cast<Decoration *>(decoration);
    if (!d) {
        return nullptr;
    }
    auto b = new Button(type, d, parent);
    const auto w = d->window();
    auto follow = [b](bool visible) { b->setVisible(visible); };
    switch (type) {
    case DecorationButtonType::Close:
        b->setVisible(w->isCloseable());
        QObject::connect(w, &KDecoration3::DecoratedWindow::closeableChanged, b, follow);
        break;
    case DecorationButtonType::Maximize:
        b->setVisible(w->isMaximizeable());
        QObject::connect(w, &KDecoration3::DecoratedWindow::maximizeableChanged, b, follow);
        break;
    case DecorationButtonType::Minimize:
        b->setVisible(w->isMinimizeable());
        QObject::connect(w, &KDecoration3::DecoratedWindow::minimizeableChanged, b, follow);
        break;
    case DecorationButtonType::ContextHelp:
        b->setVisible(w->providesContextHelp());
        QObject::connect(w, &KDecoration3::DecoratedWindow::providesContextHelpChanged, b, follow);
        break;
    case DecorationButtonType::Shade:
        b->setVisible(w->isShadeable());
        QObject::connect(w, &KDecoration3::DecoratedWindow::shadeableChanged, b, follow);
        break;
    case DecorationButtonType::Menu:
        QObject::connect(w, &KDecoration3::DecoratedWindow::iconChanged, b, [b] { b->update(); });
        break;
    default:
        break;
    }
    return b;
}

void Button::paint(QPainter *painter, const QRectF &repaintArea)
{
    Q_UNUSED(repaintArea)
    if (!isVisible()) {
        return;
    }
    auto d = qobject_cast<Decoration *>(decoration());
    if (!d) {
        return;
    }
    const QRectF box = geometry();
    const QColor fg = d->color(ColorRole::Foreground);
    const bool close = type() == DecorationButtonType::Close;
    painter->save();
    painter->setRenderHint(QPainter::Antialiasing);
    painter->setPen(Qt::NoPen);

    // Background: hover and pressed states, and checked toggles (keep above…).
    QColor bg = Qt::transparent;
    QColor glyph = fg;
    if (!d->window()->isActive()) {
        glyph.setAlphaF(0.55);
    }
    if (isPressed()) {
        bg = close ? d->closeColor().darker(115) : QColor(fg.red(), fg.green(), fg.blue(), 38);
    } else if (isHovered()) {
        bg = close ? d->closeColor() : QColor(fg.red(), fg.green(), fg.blue(), 24);
    } else if (isChecked()) {
        bg = QColor(fg.red(), fg.green(), fg.blue(), 30);
        glyph = d->window()->palette().highlight().color().lighter(150);
    }
    if ((isHovered() || isPressed()) && close) {
        glyph = QColor(255, 255, 255);
    } else if (isHovered()) {
        glyph = fg;
    }

    if (bg.alpha() > 0) {
        painter->setBrush(bg);
        if (tile) {
            // The rightmost tile fills the window's rounded corner.
            QPainterPath path;
            const qreal r = (box.right() >= d->size().width() - 0.5) ? d->radius() : 0;
            path.moveTo(box.topLeft());
            path.lineTo(box.right() - r, box.top());
            path.arcTo(QRectF(box.right() - 2 * r, box.top(), 2 * r, 2 * r), 90, -90);
            path.lineTo(box.bottomRight());
            path.lineTo(box.bottomLeft());
            path.closeSubpath();
            painter->drawPath(path);
        } else {
            painter->drawRoundedRect(box, GhostRadius, GhostRadius);
        }
    }

    const QRectF g(box.center() - QPointF(GlyphSize / 2, GlyphSize / 2), QSizeF(GlyphSize, GlyphSize));
    if (type() == DecorationButtonType::Menu) {
        d->window()->icon().paint(painter, g.toRect());
    } else {
        paintGlyph(painter, g, glyph);
    }
    painter->restore();
}

// Line glyphs on a 16 px box, 1 px strokes: KDE's rule for small monochrome
// icons, and the weight of our Lucide line icons.
void Button::paintGlyph(QPainter *painter, const QRectF &box, const QColor &color) const
{
    QPen pen(color, 1.0);
    pen.setCapStyle(Qt::RoundCap);
    pen.setJoinStyle(Qt::RoundJoin);
    painter->setPen(pen);
    painter->setBrush(Qt::NoBrush);
    // Half a pixel in: a 1 px line on whole coordinates would straddle two
    // pixel rows and turn grey. Rectangles below are drawn at x.0 for this.
    painter->translate(box.topLeft() + QPointF(0.5, 0.5));
    // Glyph coordinates are pixel centers. Straight lines are 1 px; diagonals
    // get 1.3 px, or a 45° line smears into grey and looks lighter than the
    // straight ones next to it. Glyphs with a middle vertical are 9 px wide
    // (3–11, centered on 7) so that vertical lands on a pixel.
    auto line = [painter, &pen](qreal x1, qreal y1, qreal x2, qreal y2) {
        pen.setWidthF(x1 != x2 && y1 != y2 ? 1.3 : 1.0);
        painter->setPen(pen);
        painter->drawLine(QPointF(x1, y1), QPointF(x2, y2));
    };
    auto d = qobject_cast<Decoration *>(decoration());
    switch (type()) {
    case DecorationButtonType::Minimize:
        line(3, 8, 12, 8);
        break;
    case DecorationButtonType::Maximize:
        if (d && d->window()->isMaximized()) {
            painter->drawRoundedRect(QRectF(3, 5, 7, 7), 1.5, 1.5);
            QPainterPath back;
            back.moveTo(5, 3);
            back.lineTo(10.5, 3);
            back.quadTo(12, 3, 12, 4.5);
            back.lineTo(12, 10);
            painter->drawPath(back);
        } else {
            painter->drawRoundedRect(QRectF(3, 3, 9, 9), 2, 2);
        }
        break;
    case DecorationButtonType::Close:
        line(3, 3, 12, 12);
        line(12, 3, 3, 12);
        break;
    case DecorationButtonType::KeepAbove: // arrow up to a bar
        line(3, 3, 11, 3);
        line(7, 6, 7, 13);
        line(4, 9, 7, 6), line(10, 9, 7, 6);
        break;
    case DecorationButtonType::KeepBelow: // arrow down to a bar
        line(3, 12, 11, 12);
        line(7, 2, 7, 9);
        line(4, 6, 7, 9), line(10, 6, 7, 9);
        break;
    case DecorationButtonType::OnAllDesktops: // push pin
        line(4, 2, 10, 2);
        line(5, 2, 5, 6), line(9, 2, 9, 6);
        line(5, 6, 3, 9), line(9, 6, 11, 9);
        line(3, 9, 11, 9);
        line(7, 9, 7, 14);
        break;
    case DecorationButtonType::Shade:
        line(3, 4, 11, 4);
        line(4, 7, 7, 10), line(10, 7, 7, 10);
        break;
    case DecorationButtonType::ContextHelp: {
        pen.setWidthF(1.15);
        painter->setPen(pen);
        QPainterPath q;
        q.moveTo(5, 6);
        q.cubicTo(5, 3.5, 10, 3.5, 10, 6);
        q.cubicTo(10, 8, 7, 8, 7, 10);
        painter->drawPath(q);
        painter->drawPoint(QPointF(7, 12));
        break;
    }
    case DecorationButtonType::ApplicationMenu:
        line(3, 4, 12, 4), line(3, 8, 12, 8), line(3, 12, 12, 12);
        break;
    default:
        break;
    }
}

// ---------------------------------------------------------------------------

bool Decoration::init()
{
    m_left = new KDecoration3::DecorationButtonGroup(KDecoration3::DecorationButtonGroup::Position::Left, this, &Button::create);
    m_right = new KDecoration3::DecorationButtonGroup(KDecoration3::DecorationButtonGroup::Position::Right, this, &Button::create);

    const auto w = window();
    const auto relayout = [this] { updateLayout(); };
    const auto repaint = [this] { update(); };
    for (auto signal : {&KDecoration3::DecoratedWindow::widthChanged, &KDecoration3::DecoratedWindow::heightChanged}) {
        connect(w, signal, this, relayout);
    }
    connect(w, &KDecoration3::DecoratedWindow::maximizedChanged, this, relayout);
    connect(w, &KDecoration3::DecoratedWindow::adjacentScreenEdgesChanged, this, relayout);
    connect(w, &KDecoration3::DecoratedWindow::nextScaleChanged, this, relayout);
    connect(w, &KDecoration3::DecoratedWindow::shadedChanged, this, relayout);
    connect(w, &KDecoration3::DecoratedWindow::activeChanged, this, [this] {
        updateShadow();
        update();
    });
    connect(w, &KDecoration3::DecoratedWindow::captionChanged, this, repaint);
    connect(w, &KDecoration3::DecoratedWindow::paletteChanged, this, [this] {
        updateLayout(); // the outline color comes from the palette
        update();
    });
    const auto s = settings();
    connect(s.get(), &KDecoration3::DecorationSettings::decorationButtonsLeftChanged, this, relayout);
    connect(s.get(), &KDecoration3::DecorationSettings::decorationButtonsRightChanged, this, relayout);
    connect(s.get(), &KDecoration3::DecorationSettings::fontChanged, this, repaint);
    connect(s.get(), &KDecoration3::DecorationSettings::reconfigured, this, [this] {
        readExceptions();
        updateLayout();
    });
    connect(w, &KDecoration3::DecoratedWindow::captionChanged, this, [this] {
        const bool was = m_hideTitleBar;
        readExceptions(); // title exceptions can start or stop matching
        if (was != m_hideTitleBar) {
            updateLayout();
        }
    });

    readExceptions();
    updateLayout();
    updateShadow();
    return true;
}

// The window exceptions are Breeze's (breezerc, written by lodestar's
// breeze-exceptions:), so one list serves both decorations. Only their
// "hide title bar" matters here; matched like Breeze: the pattern is a regular
// expression on the window class (type 0) or title (type 1).
void Decoration::readExceptions()
{
    m_hideTitleBar = false;
    const auto config = KSharedConfig::openConfig(QStringLiteral("breezerc"));
    config->reparseConfiguration();
    for (const QString &name : config->groupList()) {
        if (!name.startsWith(QLatin1String("Windeco Exception"))) {
            continue;
        }
        const KConfigGroup g = config->group(name);
        const QString pattern = g.readEntry("ExceptionPattern", QString());
        if (!g.readEntry("Enabled", true) || !g.readEntry("HideTitleBar", false) || pattern.isEmpty()) {
            continue;
        }
        const QString value = g.readEntry("ExceptionType", 0) == 1 ? window()->caption() : window()->windowClass();
        if (QRegularExpression(pattern).match(value).hasMatch()) {
            m_hideTitleBar = true;
            return;
        }
    }
}

void Decoration::updateLayout()
{
    const qreal scale = window()->nextScale();
    const qreal top = frameless() ? 0 : KDecoration3::snapToPixelGrid(TitleBarHeight, scale);
    const qreal width = size().width();
    setBorders(QMarginsF(0, top, 0, 0));
    const qreal resize = isFloating() ? ResizeBorder : 0;
    setResizeOnlyBorders(QMarginsF(resize, frameless() ? resize : 0, resize, resize));
    setTitleBar(QRectF(0, 0, width, top));
    setOpaque(window()->isMaximized());

    // KWin rounds the window (content included) with these radii; the title
    // bar's own top corners are painted with the same radius.
    const qreal r = radius();
    setBorderRadius(frameless() ? KDecoration3::BorderRadius(r) : KDecoration3::BorderRadius(0, 0, r, r));
    if (isFloating()) {
        QColor line = window()->color(ColorGroup::Active, ColorRole::Foreground);
        line.setAlphaF(0.10);
        const qreal px = std::max(KDecoration3::pixelSize(scale), KDecoration3::snapToPixelGrid(1, scale));
        setBorderOutline(KDecoration3::BorderOutline(px, line, KDecoration3::BorderRadius(r)));
    } else {
        setBorderOutline(KDecoration3::BorderOutline());
    }

    if (frameless()) {
        for (auto group : {m_left, m_right}) {
            for (auto b : group->buttons()) {
                b->setVisible(false);
            }
        }
        return;
    }
    // Ghost buttons on the left, vertically centered; tiles on the right,
    // full height, touching the window's right edge.
    m_left->setSpacing(GhostSpacing);
    for (auto b : m_left->buttons()) {
        b->setGeometry(QRectF(0, 0, GhostSize, GhostSize));
        static_cast<Button *>(b)->tile = false;
    }
    m_left->setPos(QPointF(SidePadding, (top - GhostSize) / 2));
    m_right->setSpacing(0);
    for (auto b : m_right->buttons()) {
        b->setGeometry(QRectF(0, 0, TileWidth, top));
        static_cast<Button *>(b)->tile = true;
    }
    m_right->setPos(QPointF(width - m_right->geometry().width(), 0));
    update();
}

void Decoration::paint(QPainter *painter, const QRectF &repaintArea)
{
    if (frameless()) {
        return;
    }
    const qreal r = radius();
    const QRectF bar(0, 0, size().width(), borderTop());
    painter->save();
    painter->setRenderHint(QPainter::Antialiasing);
    painter->setPen(Qt::NoPen);
    painter->setBrush(color(ColorRole::TitleBar));
    QPainterPath path;
    path.moveTo(bar.bottomLeft());
    path.lineTo(bar.left(), bar.top() + r);
    path.arcTo(QRectF(bar.left(), bar.top(), 2 * r, 2 * r), 180, -90);
    path.lineTo(bar.right() - r, bar.top());
    path.arcTo(QRectF(bar.right() - 2 * r, bar.top(), 2 * r, 2 * r), 90, -90);
    path.lineTo(bar.bottomRight());
    path.closeSubpath();
    painter->drawPath(path);

    // Title: centered on the window, unless the buttons are in the way.
    const qreal leftEdge = m_left->geometry().right() + 8;
    const qreal rightEdge = m_right->geometry().left() - 8;
    if (rightEdge > leftEdge) {
        painter->setFont(settings()->font());
        painter->setPen(window()->isActive() ? color(ColorRole::Foreground)
                                             : window()->color(ColorGroup::Inactive, ColorRole::Foreground));
        const QFontMetricsF fm(settings()->font());
        const QString caption = fm.elidedText(window()->caption(), Qt::ElideMiddle, rightEdge - leftEdge);
        const qreal textWidth = fm.horizontalAdvance(caption);
        QRectF text(0, 0, textWidth, bar.height());
        text.moveCenter(bar.center());
        if (text.left() < leftEdge) {
            text.moveLeft(leftEdge);
        } else if (text.right() > rightEdge) {
            text.moveRight(rightEdge);
        }
        painter->drawText(text, Qt::AlignCenter | Qt::TextSingleLine, caption);
    }
    painter->restore();

    m_left->paint(painter, repaintArea);
    m_right->paint(painter, repaintArea);
}

// A soft drop shadow: a rounded box, blurred (three box-blur passes come close
// to a gaussian), then cut out where the window sits.
static void boxBlur(QImage &img, int radius)
{
    if (radius < 1) {
        return;
    }
    const int w = img.width(), h = img.height();
    QList<int> line(std::max(w, h) * 4);
    auto pass = [&](bool horizontal) {
        const int outer = horizontal ? h : w, inner = horizontal ? w : h;
        for (int o = 0; o < outer; ++o) {
            auto px = [&](int i) -> QRgb * {
                return horizontal ? reinterpret_cast<QRgb *>(img.scanLine(o)) + i : reinterpret_cast<QRgb *>(img.scanLine(i)) + o;
            };
            for (int i = 0; i < inner; ++i) {
                const QRgb c = *px(i);
                line[i * 4] = qAlpha(c), line[i * 4 + 1] = qRed(c), line[i * 4 + 2] = qGreen(c), line[i * 4 + 3] = qBlue(c);
            }
            for (int ch = 0; ch < 4; ++ch) {
                int sum = 0;
                for (int i = -radius; i <= radius; ++i) {
                    sum += line[std::clamp(i, 0, inner - 1) * 4 + ch];
                }
                QList<int> out(inner);
                for (int i = 0; i < inner; ++i) {
                    out[i] = sum / (2 * radius + 1);
                    sum += line[std::clamp(i + radius + 1, 0, inner - 1) * 4 + ch] - line[std::clamp(i - radius, 0, inner - 1) * 4 + ch];
                }
                for (int i = 0; i < inner; ++i) {
                    QRgb *p = px(i);
                    const int v = out[i];
                    *p = ch == 0 ? qRgba(qRed(*p), qGreen(*p), qBlue(*p), v)
                       : ch == 1 ? qRgba(v, qGreen(*p), qBlue(*p), qAlpha(*p))
                       : ch == 2 ? qRgba(qRed(*p), v, qBlue(*p), qAlpha(*p))
                                 : qRgba(qRed(*p), qGreen(*p), v, qAlpha(*p));
                }
            }
        }
    };
    for (int i = 0; i < 3; ++i) {
        pass(true);
        pass(false);
    }
}

void Decoration::updateShadow()
{
    // Two layers, like Breeze's "medium" shadow: a wide soft one and a tight
    // one that grounds the window. Half as strong behind inactive windows.
    struct Layer {
        qreal offsetY, blur, opacity;
    };
    const Layer layers[] = {{8, 32, 0.55}, {2, 8, 0.25}};
    const qreal strength = window()->isActive() ? 1.0 : 0.5;
    const int pad = 64;
    const QSize box(2 * CornerRadius + 4, 2 * CornerRadius + 4);
    QImage image(box + QSize(2 * pad, 2 * pad), QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    for (const Layer &l : layers) {
        QImage layer(image.size(), QImage::Format_ARGB32_Premultiplied);
        layer.fill(Qt::transparent);
        QPainter p(&layer);
        p.setRenderHint(QPainter::Antialiasing);
        p.setPen(Qt::NoPen);
        p.setBrush(QColor(0, 0, 0, int(255 * l.opacity * strength)));
        p.drawRoundedRect(QRectF(QPointF(pad, pad + l.offsetY), box), CornerRadius, CornerRadius);
        p.end();
        boxBlur(layer, int(l.blur / 3));
        QPainter c(&image);
        c.drawImage(0, 0, layer);
    }
    // Cut out the window itself, slightly inside its edge.
    const QMarginsF padding(pad - 4, pad - 4, pad - 4, pad - 4);
    QPainter cut(&image);
    cut.setRenderHint(QPainter::Antialiasing);
    cut.setPen(Qt::NoPen);
    cut.setBrush(Qt::black);
    cut.setCompositionMode(QPainter::CompositionMode_DestinationOut);
    cut.drawRoundedRect(QRectF(image.rect()) - padding - QMarginsF(2, 2, 2, 2), CornerRadius, CornerRadius);
    cut.end();

    auto shadow = std::make_shared<KDecoration3::DecorationShadow>();
    shadow->setPadding(padding);
    shadow->setInnerShadowRect(QRectF(QRectF(image.rect()).center(), QSizeF(1, 1)));
    shadow->setShadow(image);
    setShadow(shadow);
}

} // namespace Nalthis

K_PLUGIN_FACTORY_WITH_JSON(NalthisDecorationFactory, "nalthis-decoration.json", registerPlugin<Nalthis::Decoration>(); registerPlugin<Nalthis::Button>();)

#include "nalthis-decoration.moc"
