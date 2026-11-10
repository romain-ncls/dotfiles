// hyprslide: workspace switches that slide the way the next workspace lies,
// diagonals included, as KDE's desktops do; that leave out the windows
// lying beside the screen (the scrolling layout's other columns), which a
// slide would otherwise carry across it; and that take a window along
// (Meta+Ctrl+Shift+arrow): it stays in sight, going from where it was to
// its place on the next workspace while the workspaces slide under it, as
// KWin's does.
//
// Hyprland slides sideways or up and down only, the direction from the
// workspaces' ids. The config says where the next workspace lies before it
// switches, and resets it after:
//
//     hl.plugin.hyprslide.towards(1, -1) -- to the right, above
//     hl.plugin.hyprslide.carry(window)  -- one going there, before it moves
//     monitor:set_workspace(...)
//     hl.plugin.hyprslide.towards(0, 0)  -- Hyprland's own animation again
//
// Built against the exact Hyprland it runs in (modules/hyprslide).

#include <hyprland/src/animation/WorkspaceAnimationController.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/workspace/HLWorkspace.hpp>

#include <lua.hpp>

#include <algorithm>
#include <stdexcept>

namespace {

    HANDLE         handle = nullptr;
    CFunctionHook* startHook = nullptr;
    CFunctionHook* renderHook = nullptr;
    CFunctionHook* floatHook = nullptr;

    // Where the next workspace lies: -1, 0 or 1 on each axis (x: to the
    // right, y: below). 0, 0: not ours to move.
    int dx = 0, dy = 0;

    // The window taken along to the next workspace, and where it was on the
    // screen before it moved; those taken along, while they go to their
    // place.
    PHLWINDOWREF              carried;
    CBox                      from;
    std::vector<PHLWINDOWREF> going;

    using StartAnimation = void (*)(PHLWORKSPACE, Animation::Workspace::eAnimationType, bool, bool, std::optional<std::string>);
    using ShouldRenderWindow = bool (*)(void*, PHLWINDOW, PHLMONITOR);
    using OnWorkspaceAnimUpdate = void (*)(Desktop::View::CWindowPresentation*);
    using Curve = Hyprutils::Memory::CSharedPointer<Hyprutils::Animation::SAnimationPropertyConfig>;
    using Var = Hyprutils::Memory::CWeakPointer<Hyprutils::Animation::CBaseAnimatedVariable>;

    bool special(const PHLWORKSPACE& ws) {
        return ws->type() == Workspace::eWorkspaceType::SPECIAL;
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

    // The window taken along, on the workspace coming in: on the screen, it
    // lies at its position plus the workspace's offset, which goes from
    // away to 0. Its position goes from where it was less away to its place
    // on the workspace, on the workspace's curve: so it goes straight from
    // one to the other while the workspaces slide. Hyprland fades a window
    // out of the workspace it leaves: not this one, it never leaves.
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
    // workspace slides, by how much it lies over (Hyprland's floating
    // offset). One taken along starts a screen away: that would undo it.
    void onWorkspaceAnimUpdate(Desktop::View::CWindowPresentation* self) {
        if (goingOne([self](const PHLWINDOW& w) { return &w->presentation() == self; })) {
            self->clearFloatingOffset();
            return;
        }
        reinterpret_cast<OnWorkspaceAnimUpdate>(floatHook->m_original)(self);
    }

    // Hyprland sets the switch up (the animation's config, the windows'
    // updates), then the offsets are set again on both axes: the workspace
    // coming in starts a screen away and comes to rest, the one going out
    // leaves a screen away the other way. A plain slide, whatever the style
    // (a fade would fight it).
    void startAnimation(PHLWORKSPACE ws, Animation::Workspace::eAnimationType type, bool left, bool instant, std::optional<std::string> style) {
        reinterpret_cast<StartAnimation>(startHook->m_original)(ws, type, left, instant, style);
        if ((dx == 0 && dy == 0) || instant || !ws || special(ws))
            return;
        const auto monitor = ws->m_monitor.lock();
        if (!monitor)
            return;
        const Vector2D away{dx * monitor->m_size.x, dy * monitor->m_size.y};
        ws->m_alpha->setValueAndWarp(1.F);
        if (type == Animation::Workspace::ANIMATION_TYPE_IN) {
            ws->m_renderOffset->setValueAndWarp(away);
            *ws->m_renderOffset = Vector2D{0, 0};
            if (const auto w = carried.lock(); w && w->m_workspace == ws)
                takeAlong(w, ws, away);
        } else
            *ws->m_renderOffset = Vector2D{-away.x, -away.y};
    }

    // While a workspace slides, Hyprland draws all of its windows, those
    // beside the screen too: a tiled window that lies beside it at rest stays
    // out of the switch, as a KDE desktop is the screen's rectangle. Beside:
    // the middle of its place (where it goes, not where it is: a window
    // taken along starts a screen away) is off the screen (the scrolling
    // layout parks a column with its border a few pixels over the edge).
    //
    // Hyprland leaves out a window whose box (its position, without its
    // workspace's offset) is off the screen: one taken along starts a
    // screen away, and is on it once the offset is added.
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
        if (!ws || special(ws) || ws->m_monitor != monitor || !ws->m_renderOffset->isBeingAnimated())
            return render;
        const CBox screen{monitor->m_position, monitor->m_size};
        const CBox place{window->positionAnimation()->goal(), window->sizeAnimation()->goal()};
        return screen.containsPoint(place.middle());
    }

    // hl.plugin.hyprslide.towards(dx, dy); 0, 0 also forgets a window to
    // take along that didn't go
    int towards(lua_State* L) {
        dx = std::clamp(static_cast<int>(luaL_checkinteger(L, 1)), -1, 1);
        dy = std::clamp(static_cast<int>(luaL_checkinteger(L, 2)), -1, 1);
        if (dx == 0 && dy == 0)
            carried.reset();
        return 0;
    }

    // hl.plugin.hyprslide.carry(window): where it is on the screen, before
    // it moves to the workspace coming in. Hyprland's Lua window is a
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
    if (!HyprlandAPI::addLuaFunction(handle, "hyprslide", "towards", towards) || !HyprlandAPI::addLuaFunction(handle, "hyprslide", "carry", carry))
        fail("can't add hl.plugin.hyprslide's functions");
    return {"hyprslide", "Workspace switches that slide the way the workspace lies", "Romain Nicolas", "2"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    // Hyprland removes the hooks and the Lua function itself.
}
