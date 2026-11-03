// hyprslide: workspace switches that slide the way the next workspace lies,
// diagonals included, as KDE's desktops do; and that leave out the windows
// lying beside the screen (the scrolling layout's other columns), which a
// slide would otherwise carry across it.
//
// Hyprland slides sideways or up and down only, the direction from the
// workspaces' ids. The config says where the next workspace lies before it
// switches, and resets it after:
//
//     hl.plugin.hyprslide.towards(1, -1) -- to the right, above
//     monitor:set_workspace(...)
//     hl.plugin.hyprslide.towards(0, 0)  -- Hyprland's own animation again
//
// Built against the exact Hyprland it runs in (modules/hyprslide).

#include <hyprland/src/animation/WorkspaceAnimationController.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
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

    // Where the next workspace lies: -1, 0 or 1 on each axis (x: to the
    // right, y: below). 0, 0: not ours to move.
    int dx = 0, dy = 0;

    using StartAnimation = void (*)(PHLWORKSPACE, Animation::Workspace::eAnimationType, bool, bool, std::optional<std::string>);
    using ShouldRenderWindow = bool (*)(void*, PHLWINDOW, PHLMONITOR);

    bool special(const PHLWORKSPACE& ws) {
        return ws->type() == Workspace::eWorkspaceType::SPECIAL;
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
        } else
            *ws->m_renderOffset = Vector2D{-away.x, -away.y};
    }

    // While a workspace slides, Hyprland draws all of its windows, those
    // beside the screen too: a tiled window that lies beside it at rest stays
    // out of the switch, as a KDE desktop is the screen's rectangle. Beside:
    // its middle is off the screen (the scrolling layout parks a column with
    // its border a few pixels over the edge).
    bool shouldRenderWindow(void* self, PHLWINDOW window, PHLMONITOR monitor) {
        const bool render = reinterpret_cast<ShouldRenderWindow>(renderHook->m_original)(self, window, monitor);
        if (!render || !window || !monitor || window->isFloating())
            return render;
        const auto ws = window->m_workspace;
        if (!ws || special(ws) || ws->m_monitor != monitor || !ws->m_renderOffset->isBeingAnimated())
            return render;
        const CBox screen{monitor->m_position, monitor->m_size};
        return screen.containsPoint(window->getFullWindowBoundingBox().middle());
    }

    // hl.plugin.hyprslide.towards(dx, dy)
    int towards(lua_State* L) {
        dx = std::clamp(static_cast<int>(luaL_checkinteger(L, 1)), -1, 1);
        dy = std::clamp(static_cast<int>(luaL_checkinteger(L, 2)), -1, 1);
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
    if (!HyprlandAPI::addLuaFunction(handle, "hyprslide", "towards", towards))
        fail("can't add hl.plugin.hyprslide.towards");
    return {"hyprslide", "Workspace switches that slide the way the workspace lies", "Romain Nicolas", "1"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    // Hyprland removes the hooks and the Lua function itself.
}
