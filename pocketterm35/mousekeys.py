#!/usr/bin/env python3
import asyncio
import evdev
from evdev import ecodes as e, UInput, categorize

SOURCE_DEV = "/dev/input/by-id/usb-My_Company_My_Custom_Pico_DE65A8609F687D28-if02-event-kbd"
TOGGLE_KEY = e.KEY_CAPSLOCK
MOVE_KEYS = {e.KEY_UP: (0, -1), e.KEY_DOWN: (0, 1), e.KEY_LEFT: (-1, 0), e.KEY_RIGHT: (1, 0)}
CLICK_KEYS = {e.KEY_L: e.BTN_LEFT, e.KEY_R: e.BTN_RIGHT}
SPEED = 6           # px per tick
TICK = 0.012         # seconds between ticks

mouse_mode = False
held_dirs = set()


def build_uinput(src):
    cap = {c: list(codes) for c, codes in src.capabilities().items() if c != e.EV_SYN}
    cap[e.EV_REL] = [e.REL_X, e.REL_Y]
    cap.setdefault(e.EV_KEY, [])
    for code in (e.BTN_LEFT, e.BTN_RIGHT):
        if code not in cap[e.EV_KEY]:
            cap[e.EV_KEY].append(code)
    return UInput(cap, name="mousekeys-virtual")


async def move_loop(ui):
    while True:
        await asyncio.sleep(TICK)
        if not mouse_mode or not held_dirs:
            continue
        dx = dy = 0
        for k in held_dirs:
            vx, vy = MOVE_KEYS[k]
            dx += vx
            dy += vy
        if dx or dy:
            ui.write(e.EV_REL, e.REL_X, dx * SPEED)
            ui.write(e.EV_REL, e.REL_Y, dy * SPEED)
            ui.syn()


async def main():
    src = evdev.InputDevice(SOURCE_DEV)
    src.grab()
    ui = build_uinput(src)
    global mouse_mode

    asyncio.ensure_future(move_loop(ui))

    async for ev in src.async_read_loop():
        if ev.type != e.EV_KEY:
            ui.write_event(ev)
            ui.syn()
            continue

        key = categorize(ev)
        code = key.scancode
        down = key.keystate in (key.key_down, key.key_hold)

        if code == TOGGLE_KEY:
            if key.keystate == key.key_down:
                mouse_mode = not mouse_mode
                held_dirs.clear()
                try:
                    src.set_led(e.LED_CAPSL, 1 if mouse_mode else 0)
                except OSError:
                    pass
            continue

        if mouse_mode and code in MOVE_KEYS:
            if down:
                held_dirs.add(code)
            else:
                held_dirs.discard(code)
            continue

        if mouse_mode and code in CLICK_KEYS:
            if key.keystate == key.key_down:
                ui.write(e.EV_KEY, CLICK_KEYS[code], 1)
                ui.syn()
            elif key.keystate == key.key_up:
                ui.write(e.EV_KEY, CLICK_KEYS[code], 0)
                ui.syn()
            continue

        ui.write_event(ev)
        ui.syn()


if __name__ == "__main__":
    asyncio.run(main())
