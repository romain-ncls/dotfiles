// hyprslide: the grid's desktops as one plane, as KDE's. A switch slides it
// the way the next desktop lies, diagonals included: the desktops between
// pass by (from 1 to 4, 2 and 3 through the corners), and a switch made
// while one slides goes on from where the plane is. Four fingers on the
// touchpad drag it, along one axis or, clearly diagonal, both; let go, it
// goes on to the desktop it was dragged towards, or back. The windows
// beside the screen (the scrolling layout's other columns) stay out of it:
// a KDE desktop is the screen's rectangle. A window taken along
// (Meta+Ctrl+Shift+arrow) stays in sight, going from where it was to its
// place on the next desktop while the plane slides under it, as KWin's.
//
// The config says where the desktops lie (each screen's, row by row; again
// whenever that changes), and switches when a swipe lands:
//
//     hl.plugin.hyprslide.grid({ columns = 2, fingers = 4, screens = {
//         ["DP-3"] = { "1", "2", "3", "4" }, ["HDMI-A-1"] = { "5", "6", "7", "8" } } })
//     hl.on("hyprslide.swipe", function(d) ... end) -- to desktop d, from 1
//     hl.plugin.hyprslide.carry(window)                -- one going there, before it moves
//
// Built against the exact Hyprland it runs in (modules/hyprslide).

#include <hyprland/src/animation/WorkspaceAnimationController.hpp>
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/state/workspace/Resolver.hpp>
#include <hyprland/src/state/workspace/State.hpp>
#include <hyprland/src/workspace/HLWorkspace.hpp>

#include <lua.hpp>

#include <algorithm>
#include <cmath>
#include <optional>
#include <stdexcept>
#include <utility>

namespace {

    HANDLE                                 handle = nullptr;
    CFunctionHook*                         startHook = nullptr;
    CFunctionHook*                         renderHook = nullptr;
    CFunctionHook*                         floatHook = nullptr;
    Hyprutils::Signal::CHyprSignalListener beginListener, updateListener, endListener, reloadListener;
    SP<Event::CEventBus::CCustomEvent>     swiped;

    using StartAnimation = void (*)(PHLWORKSPACE, Animation::Workspace::eAnimationType, bool, bool, std::optional<std::string>);
    using ShouldRenderWindow = bool (*)(void*, PHLWINDOW, PHLMONITOR);
    using OnWorkspaceAnimUpdate = void (*)(Desktop::View::CWindowPresentation*);
    using Curve = Hyprutils::Memory::CSharedPointer<Hyprutils::Animation::SAnimationPropertyConfig>;
    using Var = Hyprutils::Memory::CWeakPointer<Hyprutils::Animation::CBaseAnimatedVariable>;

    // The grid: each screen's desktops (workspaces, as the config names
    // them), row by row, columns to a row; the fingers that drag it.
    // columns 0: none, Hyprland's own switches.
    struct Screen {
        std::string              monitor;
        std::vector<std::string> desktops;
    };
    std::vector<Screen> screens;
    int                 columns = 0, fingers = 4;

    // The window taken along to the next desktop, and where it was on the
    // screen before it moved; those taken along, while they go to their
    // place.
    PHLWINDOWREF              carried;
    CBox                      from;
    std::vector<PHLWINDOWREF> going;

    // A switch under way: Hyprland starts the desktop going out, then the
    // one coming in. Its screen, the one going out, and where the plane lay.
    struct Leaving {
        PHLMONITORREF   monitor;
        PHLWORKSPACEREF ws;
        Vector2D        plane;
    };
    std::optional<Leaving> leaving;

    bool special(const PHLWORKSPACE& ws) {
        return ws->type() == Workspace::eWorkspaceType::SPECIAL;
    }

    const Screen* screenOf(const PHLMONITOR& m) {
        if (!m || columns <= 0)
            return nullptr;
        for (const auto& s : screens)
            if (s.monitor == m->m_name)
                return &s;
        return nullptr;
    }

    // Desktop i of a screen, if it's there (on that screen: one shown
    // elsewhere isn't on this plane).
    PHLWORKSPACE desktop(const Screen& s, size_t i, const PHLMONITOR& m) {
        const auto target = State::Workspace::resolver()->getWorkspaceTargetFromString(s.desktops[i], m);
        if (!target.valid())
            return nullptr;
        const auto ws = State::Workspace::state()->find(target);
        return ws && ws->m_monitor == m && !special(ws) ? ws : nullptr;
    }

    std::optional<size_t> indexOf(const Screen& s, const PHLWORKSPACE& ws, const PHLMONITOR& m) {
        if (!ws)
            return std::nullopt;
        for (size_t i = 0; i < s.desktops.size(); ++i)
            if (desktop(s, i, m) == ws)
                return i;
        return std::nullopt;
    }

    // Where desktop i lies: its column and row.
    Vector2D cell(size_t i) {
        return {static_cast<double>(i % columns), static_cast<double>(i / columns)};
    }

    // From start to goal on the given curve, then the variable's own again.
    // The callback once it's under way (set on a variable at rest, it runs
    // at once); the variable is a window's, owned by it: used through the
    // weak pointer, never locked (that asserts).
    void animate(PHLANIMVAR<Vector2D>& var, const Vector2D& start, const Vector2D& goal, const Curve& curve) {
        var->setValueAndWarp(start);
        if (start == goal)
            return;
        const Curve own = var->getConfig().lock();
        var->setConfig(curve);
        *var = goal;
        var->setCallbackOnEnd([own](Var v) {
            if (v && own)
                v->setConfig(own);
        });
    }

    // The window taken along, on the desktop coming in: on the screen, it
    // lies at its position plus the desktop's offset, which goes from away
    // to 0. Its position goes from where it was less away to its place on
    // the desktop, on the desktop's curve: so it goes straight from one to
    // the other while the plane slides. Hyprland fades a window out of the
    // desktop it leaves: not this one, it never leaves.
    void takeAlong(const PHLWINDOW& w, const PHLWORKSPACE& ws, const Vector2D& away) {
        carried.reset();
        const Curve curve = ws->m_renderOffset->getConfig().lock();
        if (!curve)
            return;
        const Vector2D place = w->positionAnimation()->goal(), size = w->sizeAnimation()->goal();
        animate(w->positionAnimation(), from.pos() - away, place, curve);
        animate(w->sizeAnimation(), from.size(), size, curve);
        w->presentation().alpha(Desktop::View::WINDOW_ALPHA_MOVE_TO_WORKSPACE)->setValueAndWarp(1.F);
        std::erase_if(going, [](const PHLWINDOWREF& g) { return !g; });
        going.emplace_back(w);
    }

    // The window taken along that is, while it goes to its place; the ones
    // there forgotten.
    template <typename Is>
    PHLWINDOW goingOne(Is is) {
        for (auto it = going.begin(); it != going.end();) {
            const auto w = it->lock();
            if (!w || !w->positionAnimation()->isBeingAnimated()) {
                it = going.erase(it);
                continue;
            }
            if (is(w))
                return w;
            ++it;
        }
        return nullptr;
    }

    // A floating window that lies over the screen's edge is moved, while its
    // desktop slides, by how much it lies over (Hyprland's floating offset).
    // One taken along starts a screen away: that would undo it.
    void onWorkspaceAnimUpdate(Desktop::View::CWindowPresentation* self) {
        if (goingOne([self](const PHLWINDOW& w) { return &w->presentation() == self; })) {
            self->clearFloatingOffset();
            return;
        }
        reinterpret_cast<OnWorkspaceAnimUpdate>(floatHook->m_original)(self);
    }

    // Each desktop of the screen from where it lies on the plane laid at
    // plane (desktop a's offset) to where it lies with b on the screen, on
    // the curve of b's coming in: they move as one.
    void slide(const Screen& s, const PHLMONITOR& m, size_t a, size_t b, const Vector2D& plane, const Curve& curve) {
        for (size_t i = 0; i < s.desktops.size(); ++i) {
            const auto ws = desktop(s, i, m);
            if (!ws)
                continue;
            ws->m_alpha->setValueAndWarp(1.F);
            if (curve)
                ws->m_renderOffset->setConfig(curve);
            ws->m_renderOffset->setValueAndWarp((cell(i) - cell(a)) * m->m_size + plane);
            *ws->m_renderOffset = (cell(i) - cell(b)) * m->m_size;
        }
    }

    // Hyprland sets the switch up (the animation's config, the windows'
    // updates) and slides the two desktops its way; between two desktops of
    // the grid, the plane slides instead, from where it lies (at rest, or
    // where a slide under way or a swipe has it). A plain slide, whatever
    // the style (a fade would fight it).
    void startAnimation(PHLWORKSPACE ws, Animation::Workspace::eAnimationType type, bool left, bool instant, std::optional<std::string> style) {
        const Vector2D plane = ws ? ws->m_renderOffset->value() : Vector2D{};
        reinterpret_cast<StartAnimation>(startHook->m_original)(ws, type, left, instant, style);
        if (!ws || special(ws))
            return;
        const auto    m = ws->m_monitor.lock();
        const Screen* s = screenOf(m);
        if (type == Animation::Workspace::ANIMATION_TYPE_OUT) {
            leaving.reset();
            if (s && !instant)
                leaving = Leaving{m, ws, plane};
            return;
        }
        const auto out = std::exchange(leaving, std::nullopt);
        if (!s || instant || !out || out->monitor != m)
            return;
        const auto a = indexOf(*s, out->ws.lock(), m), b = indexOf(*s, ws, m);
        if (!a || !b || *a == *b)
            return;
        slide(*s, m, *a, *b, out->plane, ws->m_renderOffset->getConfig().lock());
        if (const auto w = carried.lock(); w && w->m_workspace == ws)
            takeAlong(w, ws, (cell(*b) - cell(*a)) * m->m_size + out->plane);
    }

    // While a desktop slides, Hyprland draws all of its windows, those
    // beside the screen too: a tiled window that lies beside it at rest stays
    // out, as a KDE desktop is the screen's rectangle. Beside: the middle of
    // its place (where it goes, not where it is: a window taken along starts
    // a screen away) is off the screen (the scrolling layout parks a column
    // with its border a few pixels over the edge). Sliding: its offset
    // moves, or is off rest (dragged).
    //
    // Hyprland leaves out a window whose box (its position, without its
    // desktop's offset) is off the screen: one taken along starts a screen
    // away, and is on it once the offset is added.
    bool shouldRenderWindow(void* self, PHLWINDOW window, PHLMONITOR monitor) {
        if (window && monitor && goingOne([&window](const PHLWINDOW& w) { return w == window; })) {
            const auto ws = window->m_workspace;
            if (ws && ws->m_monitor == monitor && ws->m_renderOffset->isBeingAnimated()) {
                CBox box = window->getFullWindowBoundingBox();
                box.translate(ws->m_renderOffset->value());
                return !box.intersection({monitor->m_position, monitor->m_size}).empty();
            }
        }
        const bool render = reinterpret_cast<ShouldRenderWindow>(renderHook->m_original)(self, window, monitor);
        if (!render || !window || !monitor || window->isFloating())
            return render;
        const auto ws = window->m_workspace;
        if (!ws || special(ws) || ws->m_monitor != monitor || (!ws->m_renderOffset->isBeingAnimated() && ws->m_renderOffset->value() == Vector2D{}))
            return render;
        const CBox screen{monitor->m_position, monitor->m_size};
        const CBox place{window->positionAnimation()->goal(), window->sizeAnimation()->goal()};
        return screen.containsPoint(place.middle());
    }

    // A swipe of ours: the screens it drags, each from the desktop it was
    // on; the axes it moves along; how far it went (in the touchpad's
    // units, a desktop away at Hyprland's workspace_swipe_distance) and
    // how fast, on each axis.
    struct Held {
        PHLMONITORREF monitor;
        size_t        from;
    };
    struct {
        bool              on = false, started = false, x = true, y = true;
        Vector2D          total, delta, speed;
        int               points = 0;
        std::vector<Held> held;
    } swipe;

    int sign(double v) {
        return (v > 0) - (v < 0);
    }

    double distance() {
        static auto d = CConfigValue<Config::INTEGER>("gestures:workspace_swipe_distance");
        return std::max<double>(1, *d);
    }

    // Each screen held, its plane where the swipe has it. A desktop over
    // the screen is drawn whatever Hyprland thinks of it.
    void drag() {
        for (const auto& h : swipe.held) {
            const auto    m = h.monitor.lock();
            const Screen* s = screenOf(m);
            if (!s)
                continue;
            const Vector2D plane = swipe.delta / distance() * m->m_size * -1.0;
            for (size_t i = 0; i < s->desktops.size(); ++i) {
                const auto ws = desktop(*s, i, m);
                if (!ws)
                    continue;
                const Vector2D at = (cell(i) - cell(h.from)) * m->m_size + plane;
                ws->m_alpha->setValueAndWarp(1.F);
                ws->m_renderOffset->setValueAndWarp(at);
                ws->m_forceRendering = std::abs(at.x) < m->m_size.x && std::abs(at.y) < m->m_size.y;
                ws->updateWindowDecos();
            }
            g_pHyprRenderer->damageMonitor(m);
        }
    }

    // The swipe over: Hyprland draws the desktops its way again (those
    // still sliding until they're there).
    void release(const std::vector<Held>& held) {
        for (const auto& h : held) {
            const auto    m = h.monitor.lock();
            const Screen* s = screenOf(m);
            if (!s)
                continue;
            for (size_t i = 0; i < s->desktops.size(); ++i)
                if (const auto ws = desktop(*s, i, m))
                    ws->m_forceRendering = false;
        }
    }

    // Four fingers on a grid's desktop (any screen's: they all go). A
    // slide under way is caught where it is.
    void begin(const IPointer::SSwipeBeginEvent& e, Event::SCallbackInfo& info) {
        swipe.on = false;
        if (columns <= 0 || static_cast<int>(e.fingers) != fingers)
            return;
        swipe.held.clear();
        for (const auto& m : State::monitorState()->monitors()) {
            const Screen* s = screenOf(m);
            if (!s)
                continue;
            if (const auto i = indexOf(*s, m->m_activeWorkspace, m))
                swipe.held.push_back({m, *i});
        }
        if (swipe.held.empty())
            return;
        info.cancelled = true;
        swipe.on = true;
        swipe.started = false;
        swipe.total = swipe.speed = {};
        swipe.points = 0;
        const auto m = swipe.held.front().monitor.lock();
        swipe.delta = m->m_activeWorkspace->m_renderOffset->value() / m->m_size * -distance();
    }

    // Along one axis, unless clearly diagonal: past 25° from both.
    constexpr double DIAGONAL = 0.47;

    void update(const IPointer::SSwipeUpdateEvent& e, Event::SCallbackInfo& info) {
        if (!swipe.on)
            return;
        info.cancelled = true;
        // switched meanwhile (a key): that switch has the plane
        for (const auto& h : swipe.held) {
            const auto    m = h.monitor.lock();
            const Screen* s = screenOf(m);
            if (!s || indexOf(*s, m->m_activeWorkspace, m) != h.from) {
                swipe.on = false;
                release(swipe.held);
                return;
            }
        }
        swipe.total += e.delta;
        if (!swipe.started) {
            const double ax = std::abs(swipe.total.x), ay = std::abs(swipe.total.y);
            if (ax < 5 && ay < 5)
                return;
            swipe.started = true;
            swipe.x = ax >= ay * DIAGONAL;
            swipe.y = ay >= ax * DIAGONAL;
        }
        static auto invert = CConfigValue<Config::INTEGER>("gestures:workspace_swipe_invert");
        Vector2D    move = *invert ? -e.delta : e.delta;
        if (!swipe.x)
            move.x = 0;
        if (!swipe.y)
            move.y = 0;
        // as far as the next desktop, none past the grid's edges
        const auto&    h = swipe.held.front();
        const Screen*  s = screenOf(h.monitor.lock());
        const Vector2D c = cell(h.from);
        const double   rows = std::ceil(static_cast<double>(s->desktops.size()) / columns), d = distance();
        const Vector2D before = swipe.delta;
        swipe.delta += move;
        swipe.delta.x = std::clamp(swipe.delta.x, c.x > 0 ? -d : 0.0, c.x < columns - 1 ? d : 0.0);
        swipe.delta.y = std::clamp(swipe.delta.y, c.y > 0 ? -d : 0.0, c.y < rows - 1 ? d : 0.0);
        const Vector2D moved = swipe.delta - before;
        ++swipe.points;
        swipe.speed = (swipe.speed * (swipe.points - 1) + Vector2D{std::abs(moved.x), std::abs(moved.y)}) / swipe.points;
        drag();
    }

    // Let go: on each axis, on to the next desktop if it went far enough
    // (Hyprland's workspace_swipe_cancel_ratio) or fast enough
    // (workspace_swipe_min_speed_to_force), as Hyprland's own swipe; the
    // config switches to it, and the plane goes on from here. Back otherwise.
    void end(const IPointer::SSwipeEndEvent& e, Event::SCallbackInfo& info) {
        if (!swipe.on)
            return;
        info.cancelled = true;
        swipe.on = false;
        const auto held = std::move(swipe.held);
        if (!swipe.started)
            return;
        static auto ratio = CConfigValue<Config::FLOAT>("gestures:workspace_swipe_cancel_ratio");
        static auto force = CConfigValue<Config::INTEGER>("gestures:workspace_swipe_min_speed_to_force");
        const double d = distance();
        const auto   goes = [&](double v, double speed) { return std::abs(v) >= 2 && (std::abs(v) >= d * *ratio || (*force && speed >= *force)); };
        const int    sx = goes(swipe.delta.x, swipe.speed.x) ? sign(swipe.delta.x) : 0;
        const int    sy = goes(swipe.delta.y, swipe.speed.y) ? sign(swipe.delta.y) : 0;
        if (const Screen* s = screenOf(held.front().monitor.lock()); s && !e.cancelled && (sx || sy)) {
            const Vector2D to = cell(held.front().from) + Vector2D{static_cast<double>(sx), static_cast<double>(sy)};
            const size_t   i = static_cast<size_t>(to.y) * columns + static_cast<size_t>(to.x);
            if (i < s->desktops.size())
                static_cast<void>(swiped->emit({static_cast<int>(i + 1)}));
        }
        for (const auto& h : held) {
            const auto    m = h.monitor.lock();
            const Screen* s = screenOf(m);
            if (!s || indexOf(*s, m->m_activeWorkspace, m) != h.from)
                continue;
            const Curve curve = m->m_activeWorkspace->m_renderOffset->getConfig().lock();
            for (size_t i = 0; i < s->desktops.size(); ++i) {
                const auto ws = desktop(*s, i, m);
                if (!ws)
                    continue;
                if (curve)
                    ws->m_renderOffset->setConfig(curve);
                *ws->m_renderOffset = (cell(i) - cell(h.from)) * m->m_size;
            }
        }
        release(held);
    }

    // hl.plugin.hyprslide.grid({ columns, fingers, screens = { [monitor
    // name] = { workspace, ... } } })
    int grid(lua_State* L) {
        luaL_checktype(L, 1, LUA_TTABLE);
        std::vector<Screen> list;
        lua_getfield(L, 1, "screens");
        if (lua_istable(L, -1)) {
            lua_pushnil(L);
            while (lua_next(L, -2)) {
                if (lua_type(L, -2) == LUA_TSTRING && lua_istable(L, -1)) {
                    Screen s{lua_tostring(L, -2), {}};
                    for (lua_Integer i = 1; i <= static_cast<lua_Integer>(lua_rawlen(L, -1)); ++i) {
                        lua_rawgeti(L, -1, i);
                        if (const char* name = lua_tostring(L, -1))
                            s.desktops.emplace_back(name);
                        lua_pop(L, 1);
                    }
                    list.push_back(std::move(s));
                }
                lua_pop(L, 1);
            }
        }
        lua_pop(L, 1);
        lua_getfield(L, 1, "columns");
        columns = std::max(0, static_cast<int>(lua_tointeger(L, -1)));
        lua_pop(L, 1);
        lua_getfield(L, 1, "fingers");
        fingers = lua_isinteger(L, -1) ? static_cast<int>(lua_tointeger(L, -1)) : 4;
        lua_pop(L, 1);
        screens = std::move(list);
        return 0;
    }

    // hl.plugin.hyprslide.carry(window): where it is on the screen, before
    // it moves to the desktop coming in. Hyprland's Lua window is a
    // reference to the window under this metatable.
    int carry(lua_State* L) {
        carried = *static_cast<PHLWINDOWREF*>(luaL_checkudata(L, 1, "HL.Window"));
        const auto w = carried.lock();
        if (!w)
            return 0;
        from = CBox{w->positionAnimation()->value(), w->sizeAnimation()->value()};
        if (w->m_workspace && !(w->m_state & Desktop::View::WINDOW_STATE_PINNED))
            from.translate(w->m_workspace->m_renderOffset->value());
        return 0;
    }

    void fail(const std::string& why) {
        HyprlandAPI::addNotification(handle, "[hyprslide] " + why, CHyprColor{1.0, 0.3, 0.3, 1.0}, 10000);
        throw std::runtime_error("[hyprslide] " + why);
    }

    // The function named name whose full signature contains part.
    void* find(const std::string& name, const std::string& part) {
        for (const auto& f : HyprlandAPI::findFunctionsByName(handle, name))
            if (f.demangled.contains(part))
                return f.address;
        return nullptr;
    }

    CFunctionHook* hook(const std::string& name, const std::string& part, void* to) {
        void* from = find(name, part);
        if (!from)
            fail("no " + name + " in this Hyprland: hyprslide needs updating");
        auto* h = HyprlandAPI::createFunctionHook(handle, from, to);
        if (!h || !h->hook())
            fail("can't hook " + name);
        return h;
    }
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE h) {
    handle = h;
    if (std::string{__hyprland_api_get_hash()} != __hyprland_api_get_client_hash())
        fail("built for another Hyprland: rebuild it (lodestar apply)");
    startHook = hook("startAnimation", "Animation::Workspace::startAnimation(", reinterpret_cast<void*>(&startAnimation));
    renderHook = hook("shouldRenderWindow", "CMonitor", reinterpret_cast<void*>(&shouldRenderWindow));
    floatHook = hook("onWorkspaceAnimUpdate", "CWindowPresentation", reinterpret_cast<void*>(&onWorkspaceAnimUpdate));
    if (!HyprlandAPI::addLuaFunction(handle, "hyprslide", "grid", grid) || !HyprlandAPI::addLuaFunction(handle, "hyprslide", "carry", carry))
        fail("can't add hl.plugin.hyprslide's functions");
    swiped = makeShared<Event::CEventBus::CCustomEvent>("hyprslide.swipe", std::vector{Event::CEventBus::CCustomEvent::TYPE_INT});
    if (!HyprlandAPI::addEvent(handle, swiped))
        fail("can't add the hyprslide.swipe event");
    // A reload starts the config in a new Lua state, which hears only the
    // events added after it: again, for its hl.on.
    reloadListener = Event::bus()->m_events.config.reloaded.listen([] {
        HyprlandAPI::removeEvent(handle, swiped->m_name);
        HyprlandAPI::addEvent(handle, swiped);
    });
    beginListener = Event::bus()->m_events.gesture.swipe.begin.listen(begin);
    updateListener = Event::bus()->m_events.gesture.swipe.update.listen(update);
    endListener = Event::bus()->m_events.gesture.swipe.end.listen(end);
    return {"hyprslide", "The grid's desktops as one plane: slides, swipes", "Romain Nicolas", "3"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    // Hyprland removes the hooks and the Lua functions itself.
    beginListener.reset();
    updateListener.reset();
    endListener.reset();
    reloadListener.reset();
    HyprlandAPI::removeEvent(handle, "hyprslide.swipe");
    swiped.reset();
}
