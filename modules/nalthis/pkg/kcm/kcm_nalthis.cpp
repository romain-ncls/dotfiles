// System Settings page for the Nalthis palette. A thin shell: every color
// computation, the save to the repo and the live apply are `nalthis`
// commands (pkg/), so the page and `nalthis tune` behave the same.

#include <KPluginFactory>
#include <KQuickConfigModule>

#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QTimer>

class KcmNalthis : public KQuickConfigModule
{
    Q_OBJECT
    Q_PROPERTY(double hue READ hue WRITE setHue NOTIFY knobsChanged)
    Q_PROPERTY(double tint READ tint WRITE setTint NOTIFY knobsChanged)
    Q_PROPERTY(double depth READ depth WRITE setDepth NOTIFY knobsChanged)
    Q_PROPERTY(double accent READ accent WRITE setAccent NOTIFY knobsChanged)
    Q_PROPERTY(QVariantMap tokens READ tokens NOTIFY knobsChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
    KcmNalthis(QObject *parent, const KPluginMetaData &data)
        : KQuickConfigModule(parent, data)
    {
        setButtons(Apply | Default);
        // Live preview, after a short pause so dragging doesn't flood KDE.
        m_preview.setSingleShot(true);
        m_preview.setInterval(250);
        // The swatches follow sooner, but still not at every slider step: each
        // refresh runs `nalthis tokens`.
        m_refresh.setSingleShot(true);
        m_refresh.setInterval(60);
        connect(&m_refresh, &QTimer::timeout, this, [this] {
            QByteArray out;
            if (run({QStringLiteral("tokens"), num(m_knobs[0]), num(m_knobs[1]), num(m_knobs[2]), num(m_knobs[3])}, &out)) {
                m_tokens = QJsonDocument::fromJson(out).object().toVariantMap();
                Q_EMIT knobsChanged();
            }
        });
        connect(&m_preview, &QTimer::timeout, this, [this] {
            if (run({QStringLiteral("apply"), num(m_knobs[0]), num(m_knobs[1]), num(m_knobs[2]), num(m_knobs[3])})) {
                m_previewed = true;
            }
        });
    }

    ~KcmNalthis() override
    {
        // Leaving with a preview showing but not saved: put the saved palette back.
        if (m_previewed) {
            QProcess::startDetached(QStringLiteral("nalthis"), {QStringLiteral("apply")});
        }
    }

    double hue() const { return m_knobs[0]; }
    double tint() const { return m_knobs[1]; }
    double depth() const { return m_knobs[2]; }
    double accent() const { return m_knobs[3]; }
    void setHue(double v) { setKnob(0, v); }
    void setTint(double v) { setKnob(1, v); }
    void setDepth(double v) { setKnob(2, v); }
    void setAccent(double v) { setKnob(3, v); }
    QVariantMap tokens() const { return m_tokens; }
    QString error() const { return m_error; }

    void load() override
    {
        QByteArray out;
        if (!run({QStringLiteral("get")}, &out)) {
            return;
        }
        const QJsonObject json = QJsonDocument::fromJson(out).object();
        m_saved = knobs(json[QStringLiteral("knobs")].toObject());
        m_defaults = knobs(json[QStringLiteral("defaults")].toObject());
        m_knobs = m_saved;
        m_tokens = json[QStringLiteral("tokens")].toObject().toVariantMap();
        if (m_previewed) { // Reset or Discard: undo the live preview
            m_preview.stop();
            m_refresh.stop();
            run({QStringLiteral("apply")});
            m_previewed = false;
        }
        Q_EMIT knobsChanged();
        updateState();
    }

    void save() override
    {
        m_preview.stop();
        if (run({QStringLiteral("set"), QStringLiteral("hue=") + num(m_knobs[0]), QStringLiteral("tint=") + num(m_knobs[1]),
                 QStringLiteral("depth=") + num(m_knobs[2]), QStringLiteral("accent=") + num(m_knobs[3])})) {
            m_saved = m_knobs;
            m_previewed = false;
        }
        updateState();
    }

    void defaults() override
    {
        for (int i = 0; i < 4; ++i) {
            setKnob(i, m_defaults[i]);
        }
    }

Q_SIGNALS:
    void knobsChanged();
    void errorChanged();

private:
    using Knobs = std::array<double, 4>;

    static QString num(double v) { return QString::number(v, 'f', 3); }

    static Knobs knobs(const QJsonObject &o)
    {
        return {o[QStringLiteral("hue")].toDouble(), o[QStringLiteral("tint")].toDouble(), o[QStringLiteral("depth")].toDouble(),
                o[QStringLiteral("accent")].toDouble()};
    }

    void setKnob(int i, double v)
    {
        if (qFuzzyCompare(1 + m_knobs[i], 1 + v)) {
            return;
        }
        m_knobs[i] = v;
        Q_EMIT knobsChanged();
        updateState();
        m_refresh.start();
        m_preview.start();
    }

    void updateState()
    {
        auto same = [](const Knobs &a, const Knobs &b) {
            for (int i = 0; i < 4; ++i) {
                if (std::abs(a[i] - b[i]) > 1e-6) {
                    return false;
                }
            }
            return true;
        };
        setNeedsSave(!same(m_knobs, m_saved));
        setRepresentsDefaults(same(m_knobs, m_defaults));
    }

    // Runs `nalthis args`, short and synchronous; shows its error on the page.
    bool run(const QStringList &args, QByteArray *out = nullptr)
    {
        QProcess p;
        p.start(QStringLiteral("nalthis"), args);
        const bool ok = p.waitForFinished(10000) && p.exitStatus() == QProcess::NormalExit && p.exitCode() == 0;
        QString error;
        if (!ok) {
            error = QString::fromUtf8(p.readAllStandardError()).trimmed();
            if (error.isEmpty()) {
                error = QStringLiteral("nalthis: ") + p.errorString();
            }
        }
        if (out) {
            *out = p.readAllStandardOutput();
        }
        if (error != m_error) {
            m_error = error;
            Q_EMIT errorChanged();
        }
        return ok;
    }

    Knobs m_knobs{255, 1, 0, 250}, m_saved = m_knobs, m_defaults = m_knobs;
    QVariantMap m_tokens;
    QString m_error;
    QTimer m_preview, m_refresh;
    bool m_previewed = false;
};

K_PLUGIN_CLASS_WITH_JSON(KcmNalthis, "kcm_nalthis.json")

#include "kcm_nalthis.moc"
