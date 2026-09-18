// Long press on a touchscreen sends a right click.
//
// Hyprland has nothing for this: its gesture system is trackpad only, and
// input.touchdevice only carries enabled/output/transform. Doing it outside the
// compositor would mean reading /dev/input and writing to /dev/uinput, so it
// lives here instead, where the touch events already are.
//
// One finger held still for LONG_PRESS_MS becomes a right click where the
// finger rests. Moving further than MOVE_TOLERANCE (a fraction of the screen)
// or putting a second finger down cancels it, so scrolling and pinching are
// untouched, and a press on a layer surface (the bar, the on-screen keyboard
// and its floating icon) is left alone, so holding a key to repeat it does not
// turn into a right click.

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopTimer.hpp>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/pointer/PointerManager.hpp>
#include <hyprland/src/devices/ITouch.hpp>
#include <hyprland/src/devices/IPointer.hpp>

#include <hyprland/src/debug/log/Logger.hpp>

#include <linux/input-event-codes.h>
#include <chrono>
#include <cmath>

static constexpr int   LONG_PRESS_MS  = 500;
// how far the finger may wander, as a fraction of the screen (about 27 px wide here)
static constexpr float MOVE_TOLERANCE = 0.02F;

inline HANDLE                     PHANDLE = nullptr;

static CHyprSignalListener        g_touchDown, g_touchUp, g_touchMotion, g_touchCancel;
static SP<CEventLoopTimer>        g_timer;
static Vector2D                   g_downPos;
static int                        g_fingers = 0;
static bool                       g_armed   = false;

static void disarm() {
    g_armed = false;
    if (g_timer)
        g_timer->updateTimeout(std::nullopt);
}

static void rightClickAtFinger() {
    if (!g_pInputManager || !g_pSeatManager || !Pointer::mgr())
        return;

    // the finger is on the bar, the on-screen keyboard, the floating icon or another
    // layer surface: those are buttons and keys, not places to open a context menu
    if (!g_pInputManager->m_touchData.touchFocusLS.expired())
        return;

    const auto  POS    = g_pInputManager->m_touchData.lastTouchPos;
    const auto  TIMEMS = (uint32_t)std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();

    // put the cursor under the finger, so the click lands where you are pressing
    Pointer::mgr()->warpTo(POS);
    g_pInputManager->refocus(POS);
    g_pInputManager->simulateMouseMovement();

    IPointer::SButtonEvent event = {
        .timeMs = TIMEMS,
        .button = BTN_RIGHT,
        .state  = WL_POINTER_BUTTON_STATE_PRESSED,
        .mouse  = true,
    };
    g_pInputManager->onMouseButton(event, g_pSeatManager->m_mouse.lock());

    event.timeMs = TIMEMS + 1;
    event.state  = WL_POINTER_BUTTON_STATE_RELEASED;
    g_pInputManager->onMouseButton(event, g_pSeatManager->m_mouse.lock());
}

static void onTimer(SP<CEventLoopTimer> self, void* data) {
    if (!g_armed || g_fingers != 1)
        return;
    g_armed = false;
    try {
        rightClickAtFinger();
    } catch (const std::exception& e) {
        // never take the compositor down over a click
        Log::logger->log(Log::ERR, "[surface-longpress] {}", e.what());
    }
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    // the compositor and the plugin must come from the same Hyprland build
    if (std::string{__hyprland_api_get_hash()} != __hyprland_api_get_client_hash()) {
        HyprlandAPI::addNotification(PHANDLE, "[surface-longpress] built against a different Hyprland, not loading",
                                     CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("[surface-longpress] version mismatch");
    }

    g_timer = makeShared<CEventLoopTimer>(std::nullopt, onTimer, nullptr);
    g_pEventLoopManager->addTimer(g_timer);

    auto& touch = Event::bus()->m_events.input.touch;

    g_touchDown = touch.down.listen([](const ITouch::SDownEvent& e, Event::SCallbackInfo& info) {
        g_fingers++;
        if (g_fingers != 1) { // a second finger means scrolling or pinching
            disarm();
            return;
        }
        g_downPos = e.pos;
        g_armed   = true;
        g_timer->updateTimeout(std::chrono::milliseconds(LONG_PRESS_MS));
    });

    g_touchMotion = touch.motion.listen([](const ITouch::SMotionEvent& e, Event::SCallbackInfo& info) {
        if (!g_armed)
            return;
        if (std::hypot(e.pos.x - g_downPos.x, e.pos.y - g_downPos.y) > MOVE_TOLERANCE)
            disarm(); // the finger is travelling: a swipe, not a press
    });

    g_touchUp = touch.up.listen([](const ITouch::SUpEvent& e, Event::SCallbackInfo& info) {
        g_fingers = std::max(0, g_fingers - 1);
        disarm();
    });

    g_touchCancel = touch.cancel.listen([](const ITouch::SCancelEvent& e, Event::SCallbackInfo& info) {
        g_fingers = std::max(0, g_fingers - 1);
        disarm();
    });

    return {"surface-longpress", "Long press on the touchscreen sends a right click", "omarchy-surface-touch", "1.0.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_touchDown.reset();
    g_touchUp.reset();
    g_touchMotion.reset();
    g_touchCancel.reset();
    if (g_timer) {
        g_timer->cancel();
        g_pEventLoopManager->removeTimer(g_timer);
        g_timer.reset();
    }
}
