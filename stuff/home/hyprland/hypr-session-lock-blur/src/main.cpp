#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/protocols/SessionLock.hpp>
#include <hyprland/src/render/pass/SurfacePassElement.hpp>
#include <hyprland/src/Compositor.hpp>

inline HANDLE PHANDLE = nullptr;
typedef void (*origRenderSessionLockSurface)(void*, WP<SSessionLockSurface>, PHLMONITOR, const Time::steady_tp&);
inline CFunctionHook* g_pRenderSessionLockHook = nullptr;

void hkRenderSessionLockSurface(void* thisptr, WP<SSessionLockSurface> pSurface, PHLMONITOR pMonitor, const Time::steady_tp& time) {
    static auto PSESSIONLOCKXRAY = CConfigValue<Config::BOOL>("misc:session_lock_xray");
    static auto PSESSIONLOCKBLUR = CConfigValue<Config::BOOL>("misc:session_lock_blur");

    CSurfacePassElement::SRenderData renderdata = {pMonitor, time, pMonitor->m_position, pMonitor->m_position};

    renderdata.blur = *PSESSIONLOCKBLUR && *PSESSIONLOCKXRAY;
    if (renderdata.blur) {
        renderdata.discardMode |= DISCARD_ALPHA;
        renderdata.discardOpacity = 0.001f;
    }
    renderdata.surface  = pSurface->surface->surface();
    renderdata.decorate = false;
    renderdata.w        = pMonitor->m_size.x;
    renderdata.h        = pMonitor->m_size.y;

    renderdata.surface->breadthfirst(
        [&renderdata, &pSurface](SP<CWLSurfaceResource> s, const Vector2D& offset, void* data) {
            if (!s->m_current.texture)
                return;

            if (s->m_current.size.x < 1 || s->m_current.size.y < 1)
                return;

            renderdata.localPos    = offset;
            renderdata.texture     = s->m_current.texture;
            renderdata.surface     = s;
            renderdata.mainSurface = s == pSurface->surface->surface();
            g_pHyprRenderer->m_renderPass.add(makeUnique<CSurfacePassElement>(renderdata));
            renderdata.surfaceCounter++;
        },
        &renderdata);
}

extern "C" {

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    const auto matches = HyprlandAPI::findFunctionsByName(PHANDLE, "renderSessionLockSurface");
    for (const auto& m : matches) {
        g_pRenderSessionLockHook = HyprlandAPI::createFunctionHook(PHANDLE, m.address, (void*)&hkRenderSessionLockSurface);
        if (g_pRenderSessionLockHook) {
            g_pRenderSessionLockHook->hook();
            break;
        }
    }

    return {"hypr-session-lock-blur", "Enables alpha-masked blur for session lock", "l0lk3k", "0.1"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    if (g_pRenderSessionLockHook) {
        g_pRenderSessionLockHook->unhook();
    }
}

}
