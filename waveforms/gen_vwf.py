#!/usr/bin/env python3
"""Generate the University VWF test cases and check simulated results against them.

  python waveforms/gen_vwf.py            write every .vwf and .qpf/.qsf
  python waveforms/gen_vwf.py --check    compare simulation/qsim/*.vcd with the models

Each scenario runs a cycle-accurate Python model of the block, so stimulus can
react to the shuffled deck, and scenario asserts state what each test proves.
Inputs change on falling clock edges; clk rises at 20k+10 ns for cycle k.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).parent
PERIOD = 20
READY, SHUFFLE, PICK_FIRST, PICK_SECOND, REVEAL, CHECK, GAME_OVER = range(7)
RTL = {
    "game_core": ["game_pkg", "game_core"],
    "input_controller": ["input_controller"],
    "vga_timing": ["vga_timing"],
    "frame_snapshot": ["game_pkg", "frame_snapshot"],
    "top": ["game_pkg", "font_pkg", "input_controller", "game_core", "vga_timing",
            "frame_snapshot", "renderer", "top"],
}


class Core:
    """Mirror of rtl/game_core.vhd with REVEAL_CYCLES = 8."""
    def __init__(self):
        self.seed = 0xACE1
        self.rng = 0xACE1
        self.count = 0
        self.i = 15
        self.rem = 0
        self.bit = 0
        self.clear()
        self.reverse = 0

    def clear(self):
        self.state = READY
        self.cards = [0, 1, 2, 3, 4, 5, 6, 7] * 2
        self.matched = 0
        self.cursor = self.first = self.second = 0
        self.two = self.player = 0
        self.score1 = self.score2 = self.pairs = self.attempts = 0

    def step(self, rst, nxt, opn, mode, rev):
        seed = self.seed
        self.seed = (seed + 1) & 0xFFFF
        if rst:
            self.clear()
            self.reverse = 0
            self.count = self.rem = self.bit = 0
            self.i = 15
            self.rng = 0xACE1
            return
        s = self.state
        if s == READY:
            self.two = mode
            if opn:
                self.clear()
                self.two = mode
                self.state = SHUFFLE
                self.i, self.rem, self.bit = 15, 0, 0
                self.rng = seed or 0xACE1
        elif s == SHUFFLE:
            if self.bit < 16:
                r = self.rem * 2 + ((self.rng >> (15 - self.bit)) & 1)
                if r >= self.i + 1:
                    r -= self.i + 1
                self.rem = r
                self.bit += 1
            else:
                c = self.cards
                c[self.i], c[self.rem] = c[self.rem], c[self.i]
                g = self.rng
                fb = ((g >> 15) ^ (g >> 13) ^ (g >> 12) ^ (g >> 10)) & 1
                self.rng = ((g << 1) & 0xFFFF) | fb
                self.rem = self.bit = 0
                if self.i == 1:
                    self.state = PICK_FIRST
                else:
                    self.i -= 1
        elif s in (PICK_FIRST, PICK_SECOND):
            if opn:
                if not (self.matched >> self.cursor) & 1:
                    if s == PICK_FIRST:
                        self.first = self.cursor
                        self.state = PICK_SECOND
                    elif self.cursor != self.first:
                        self.second = self.cursor
                        self.attempts = min(self.attempts + 1, 999)
                        self.count = 0
                        self.state = REVEAL
            elif nxt:
                self.cursor = (self.cursor + (-1 if rev else 1)) % 16
        elif s == REVEAL:
            if self.count == 7:
                self.state = CHECK
            else:
                self.count += 1
        elif s == CHECK:
            if self.cards[self.first] == self.cards[self.second]:
                self.matched |= (1 << self.first) | (1 << self.second)
                self.pairs += 1
                if self.player == 0:
                    self.score1 += 1
                else:
                    self.score2 += 1
                self.state = GAME_OVER if self.pairs == 8 else PICK_FIRST
            else:
                if self.two:
                    self.player ^= 1
                self.state = PICK_FIRST
        elif s == GAME_OVER:
            if opn:
                self.clear()
                self.two = mode
        self.reverse = rev


class Bench:
    """Records inputs per cycle while stepping a block model, plus expected outputs."""
    block = ""
    inputs = {}   # name -> width
    outputs = {}  # name -> width
    radix = {}

    def __init__(self):
        self.now = {k: (3 if k == "key_n" else 0) for k in self.inputs}
        self.rows = []
        self.expected = []

    def model(self):
        raise NotImplementedError

    def tick(self, n=1):
        for _ in range(n):
            self.rows.append(dict(self.now))
            self.expected.append(self.model())

    def set(self, **kw):
        self.now.update(kw)


class CoreBench(Bench):
    block = "game_core"
    inputs = {"reset_game": 1, "next_press": 1, "open_press": 1, "mode_sync": 1, "reverse_sync": 1}
    outputs = {"state": 3, "cursor": 4, "card_at_cursor": 3, "first_card": 4, "second_card": 4,
               "matched": 16, "two_players": 1, "player": 1, "reverse": 1,
               "score1": 4, "score2": 4, "pairs": 4, "attempts": 10}
    radix = {"matched": "Hexadecimal"}

    def __init__(self):
        super().__init__()
        self.g = Core()

    def model(self):
        n = self.now
        g = self.g
        g.step(n["reset_game"], n["next_press"], n["open_press"], n["mode_sync"], n["reverse_sync"])
        return {"state": g.state, "cursor": g.cursor, "card_at_cursor": g.cards[g.cursor],
                "first_card": g.first, "second_card": g.second, "matched": g.matched,
                "two_players": g.two, "player": g.player, "reverse": g.reverse,
                "score1": g.score1, "score2": g.score2, "pairs": g.pairs, "attempts": g.attempts}

    def pulse(self, name, n=1):
        self.set(**{name: 1})
        self.tick(n)
        self.set(**{name: 0})
        self.tick()

    def reset(self):
        self.pulse("reset_game")

    def start(self, mode=0):
        self.set(mode_sync=mode)
        self.tick()
        self.pulse("open_press")
        while self.g.state != PICK_FIRST:
            self.tick()
        assert self.g.two == mode
        assert sorted(self.g.cards) == sorted(list(range(8)) * 2), "shuffle lost a card"

    def goto(self, pos):
        steps = (pos - self.g.cursor) % 16
        if steps:
            self.pulse("next_press", steps)
        assert self.g.cursor == pos

    def pair(self, card):
        a, b = [i for i, c in enumerate(self.g.cards) if c == card]
        return a, b

    def resolve(self, a, b):
        self.goto(a)
        self.pulse("open_press")
        assert self.g.state == PICK_SECOND
        self.goto(b)
        self.set(open_press=1)
        self.tick()
        self.set(open_press=0)
        assert self.g.state == REVEAL
        while self.g.state in (REVEAL, CHECK):
            self.tick()
        self.tick()

    def win(self, card):
        before = self.g.player
        self.resolve(*self.pair(card))
        assert self.g.player == before

    def miss(self, c1, c2):
        self.resolve(self.pair(c1)[0], self.pair(c2)[0])


class InputBench(Bench):
    block = "input_controller"
    inputs = {"key_n": 2, "mode_switch": 1, "reset_switch": 1, "reverse_switch": 1}
    outputs = {"next_press": 1, "open_press": 1, "mode_sync": 1, "reset_game": 1, "reverse_sync": 1}
    radix = {"key_n": "Binary"}

    def __init__(self):
        super().__init__()
        self.meta = self.sync = self.stable = 3
        self.mode = [0, 0]
        self.rev = [0, 0]
        self.pipe = 3
        self.counts = [0, 0]
        self.pulses = 0
        self.total = [0, 0]

    def model(self):
        n = self.now
        if n["reset_switch"]:
            self.pipe = 3  # asynchronous assertion, before the clock edge
        sync = self.sync
        self.sync = self.meta
        self.meta = n["key_n"]
        self.mode = [n["mode_switch"], self.mode[0]]
        self.rev = [n["reverse_switch"], self.rev[0]]
        self.pulses = 0
        if self.pipe & 2:
            self.stable = 3
            self.counts = [0, 0]
        else:
            for i in range(2):
                bit = (sync >> i) & 1
                if bit == (self.stable >> i) & 1:
                    self.counts[i] = 0
                elif self.counts[i] == 3:
                    self.stable = (self.stable & ~(1 << i)) | (bit << i)
                    self.counts[i] = 0
                    if not bit:
                        self.pulses |= 1 << i
                        self.total[i] += 1
                else:
                    self.counts[i] += 1
        if not n["reset_switch"]:
            self.pipe = (self.pipe & 1) << 1
        return {"next_press": self.pulses & 1, "open_press": (self.pulses >> 1) & 1,
                "mode_sync": self.mode[1], "reset_game": (self.pipe >> 1) & 1,
                "reverse_sync": self.rev[1]}


class VgaBench(Bench):
    block = "vga_timing"
    inputs = {"reset": 1}
    outputs = {"pixel_ce": 1, "hsync": 1, "vsync": 1, "active": 1, "frame_capture": 1, "x": 10, "y": 10}

    def __init__(self):
        super().__init__()
        self.phase = self.h = self.v = 0

    def model(self):
        if self.now["reset"]:
            self.phase = self.h = self.v = 0
        else:
            if self.phase:
                if self.h == 799:
                    self.h = 0
                    self.v = 0 if self.v == 524 else self.v + 1
                else:
                    self.h += 1
            self.phase ^= 1
        h, v = self.h, self.v
        return {"pixel_ce": self.phase, "x": h, "y": v, "active": int(h < 640 and v < 480),
                "hsync": int(not 656 <= h < 752), "vsync": int(not 490 <= v < 492),
                "frame_capture": int(self.phase and h == 799 and v == 479)}


class SnapshotBench(Bench):
    block = "frame_snapshot"
    inputs = {"capture": 1, "live_cursor": 4}
    outputs = {"frame_cursor": 4}

    def __init__(self):
        super().__init__()
        self.saved = 0

    def model(self):
        if self.now["capture"]:
            self.saved = self.now["live_cursor"]
        return {"frame_cursor": self.saved}


class TopBench(Bench):
    """No model: the renderer is not mirrored; check_top asserts sync and blanking."""
    block = "top"
    inputs = {"KEY": 2, "SW": 10}
    outputs = {"VGA_HS": 1, "VGA_VS": 1, "VGA_R": 4, "VGA_G": 4, "VGA_B": 4}
    radix = {"KEY": "Binary", "SW": "Binary"}

    def __init__(self):
        super().__init__()
        self.now["KEY"] = 3

    def model(self):
        return None


# ---------------------------------------------------------------- game_core
def tc01():
    "Power-on READY, then SHUFFLE, then PICK_FIRST; walk the 16 cards: each ID appears twice"
    b = CoreBench()
    b.tick(3)
    b.reset()
    assert b.g.state == READY
    b.start(0)
    for _ in range(16):
        b.pulse("next_press")
    return b


def tc02():
    "Pressing start 5 clocks later gives a different deck (different seed)"
    b = CoreBench()
    b.tick(8)
    b.reset()
    b.start(0)
    assert b.g.cards != tc01().g.cards, "seed did not change the deck"
    for _ in range(16):
        b.pulse("next_press")
    return b


def tc03():
    "Cursor wraps 15 to 0; SW8 reverse wraps 0 to 15 then steps down; forward resumes"
    b = CoreBench()
    b.reset()
    b.start(0)
    b.goto(15)
    b.pulse("next_press")
    assert b.g.cursor == 0
    b.set(reverse_sync=1)
    b.tick()
    b.pulse("next_press")
    assert b.g.cursor == 15 and b.g.reverse == 1
    b.pulse("next_press")
    assert b.g.cursor == 14
    b.set(reverse_sync=0)
    b.tick()
    b.pulse("next_press")
    b.pulse("next_press")
    assert b.g.cursor == 0 and b.g.reverse == 0
    return b


def tc04():
    "KEY1 beats KEY0; same card and an already matched card cannot be opened"
    b = CoreBench()
    b.reset()
    b.start(0)
    b.goto(0)
    b.set(next_press=1, open_press=1)
    b.tick()
    b.set(next_press=0, open_press=0)
    b.tick()
    assert b.g.state == PICK_SECOND and b.g.first == 0 and b.g.cursor == 0
    b.pulse("open_press")
    assert b.g.state == PICK_SECOND and b.g.attempts == 0, "same card accepted"
    card = b.g.cards[0]
    other = [i for i, c in enumerate(b.g.cards) if c == card and i][0]
    b.goto(other)
    b.set(open_press=1)
    b.tick()
    b.set(open_press=0)
    while b.g.state != PICK_FIRST:
        b.tick()
    b.tick()
    attempts = b.g.attempts
    b.goto(other)
    b.pulse("open_press")
    assert b.g.state == PICK_FIRST and b.g.attempts == attempts, "matched card accepted"
    return b


def tc05():
    "Reveal lasts exactly 8 clocks and ignores keys; mismatch closes cards; mode locked in play"
    b = CoreBench()
    b.reset()
    b.start(0)
    b.set(mode_sync=1)
    b.tick(4)
    assert b.g.two == 0, "mode changed during play"
    a = b.pair(0)[0]
    c = b.pair(1)[0]
    b.goto(a)
    b.pulse("open_press")
    b.goto(c)
    b.set(open_press=1)
    b.tick()
    assert b.g.state == REVEAL and b.g.attempts == 1
    b.set(next_press=1)
    for _ in range(7):
        b.tick()
        assert b.g.state == REVEAL and b.g.cursor == c
    b.tick()
    assert b.g.state == CHECK
    b.set(next_press=0, open_press=0)
    b.tick()
    assert b.g.state == PICK_FIRST and b.g.matched == 0 and b.g.player == 0
    b.tick(3)
    return b


def tc06():
    "2 players: a mismatch switches turn; a match scores for the current player and keeps the turn"
    b = CoreBench()
    b.reset()
    b.start(1)
    b.win(0)
    assert b.g.score1 == 1 and b.g.player == 0
    b.miss(1, 2)
    assert b.g.player == 1 and b.g.score1 == 1
    b.win(1)
    assert b.g.score2 == 1 and b.g.player == 1
    b.miss(2, 3)
    assert b.g.player == 0
    b.tick(3)
    return b


def tc07():
    "2 players: Player 1 wins 8-0, GAME_OVER, final pair scored"
    b = CoreBench()
    b.reset()
    b.start(1)
    for card in range(8):
        b.win(card)
    assert b.g.state == GAME_OVER and (b.g.score1, b.g.score2) == (8, 0)
    b.tick(5)
    return b


def tc08():
    "2 players: Player 2 wins 0-8 after P1 misses"
    b = CoreBench()
    b.reset()
    b.start(1)
    b.miss(0, 1)
    for card in range(8):
        b.win(card)
    assert b.g.state == GAME_OVER and (b.g.score1, b.g.score2) == (0, 8)
    b.tick(5)
    return b


def tc09():
    "2 players: draw 4-4"
    b = CoreBench()
    b.reset()
    b.start(1)
    for card in range(4):
        b.win(card)
    b.miss(4, 5)
    for card in range(4, 8):
        b.win(card)
    assert b.g.state == GAME_OVER and (b.g.score1, b.g.score2) == (4, 4)
    b.tick(5)
    return b


def tc10():
    "1 player: full game with 9 attempts, then KEY1 replay returns to READY with a clean board"
    b = CoreBench()
    b.reset()
    b.start(0)
    b.miss(0, 1)
    for card in range(8):
        b.win(card)
    assert b.g.state == GAME_OVER and b.g.score1 == 8 and b.g.attempts == 9
    b.tick(5)
    b.pulse("open_press")
    assert b.g.state == READY and b.g.matched == 0 and b.g.attempts == 0 and b.g.score1 == 0
    b.tick(3)
    return b


def tc11():
    "SW9 reset clears the game from each of the 7 states"
    b = CoreBench()
    seen = set()

    def reset():
        seen.add(b.g.state)
        b.pulse("reset_game")
        g = b.g
        assert g.state == READY and g.matched == 0 and g.pairs == g.score1 == g.score2 == g.attempts == g.cursor == 0
    b.tick(2)
    reset()                                   # READY
    b.pulse("open_press")
    assert b.g.state == SHUFFLE
    b.tick(4)
    reset()                                   # SHUFFLE
    b.start(0)
    reset()                                   # PICK_FIRST
    b.start(0)
    b.goto(0)
    b.pulse("open_press")
    reset()                                   # PICK_SECOND
    b.start(0)
    b.pulse("open_press")
    b.goto(1)
    b.set(open_press=1)
    b.tick()
    b.set(open_press=0)
    b.tick(2)
    assert b.g.state == REVEAL
    reset()                                   # REVEAL
    b.start(0)
    b.pulse("open_press")
    b.goto(1)
    b.set(open_press=1)
    b.tick()
    b.set(open_press=0)
    b.tick(8)
    assert b.g.state == CHECK
    reset()                                   # CHECK
    b.start(1)
    for card in range(8):
        b.win(card)
    assert b.g.state == GAME_OVER
    reset()                                   # GAME_OVER
    assert seen == set(range(7))
    b.tick(3)
    return b


def tc12():
    "Attempt counter stops at 999: 1,002 mismatches run literally, score stays 0"
    b = CoreBench()
    b.reset()
    b.start(0)
    a = b.pair(0)[0]
    c = b.pair(1)[0]
    for _ in range(1002):
        b.goto(a)
        b.set(open_press=1)
        b.tick()
        b.set(open_press=0)
        b.goto(c)
        b.set(open_press=1)
        b.tick()
        b.set(open_press=0)
        b.tick(9)
        assert b.g.state == PICK_FIRST
    assert b.g.attempts == 999 and b.g.score1 == 0
    b.tick(3)
    return b


# --------------------------------------------------------- input_controller
def tc13():
    "Press bounce gives no pulse; stable press gives one pulse; hold does not repeat; release bounce ignored"
    b = InputBench()
    b.tick(10)
    assert b.expected[-1]["reset_game"] == 0, "power-on reset did not release"
    b.set(key_n=2)
    b.tick()
    b.set(key_n=3)
    b.tick()
    b.set(key_n=2)
    b.tick(2)
    b.set(key_n=3)
    b.tick(10)
    assert b.total[0] == 0, "bounce caused a press"
    b.set(key_n=2)
    b.tick(12)
    assert b.total[0] == 1
    b.tick(30)
    assert b.total[0] == 1, "held key repeated"
    b.set(key_n=3)
    b.tick()
    b.set(key_n=2)
    b.tick(12)
    assert b.total[0] == 1, "release bounce repeated"
    b.set(key_n=3)
    b.tick(12)
    return b


def tc14():
    "KEY0 and KEY1 together give one pulse each; SW0 and SW8 pass a 2-stage synchronizer"
    b = InputBench()
    b.tick(10)
    b.set(key_n=0)
    b.tick(12)
    assert b.total == [1, 1]
    b.set(key_n=3)
    b.tick(12)
    b.set(mode_switch=1)
    b.tick(4)
    assert b.expected[-1]["mode_sync"] == 1
    b.set(reverse_switch=1)
    b.tick(4)
    assert b.expected[-1]["reverse_sync"] == 1
    b.set(mode_switch=0, reverse_switch=0)
    b.tick(4)
    return b


def tc15():
    "Power-on reset; SW9 asserts reset asynchronously, releases after 2 clocks; no false key pulse"
    b = InputBench()
    b.tick(6)
    b.set(key_n=0)
    b.tick(12)
    before = list(b.total)
    b.set(reset_switch=1)
    b.tick(10)
    b.set(key_n=3, reset_switch=0)
    b.tick()
    assert b.expected[-1]["reset_game"] == 1, "release not synchronized"
    b.tick()
    assert b.expected[-1]["reset_game"] == 0
    b.tick(10)
    assert b.total == before, "reset generated a button pulse"
    return b


# --------------------------------------------------------------- video
def tc16():
    "Two VGA lines: pixel_ce every 2 clocks, active 640 px, HSYNC low 96 px, line 800 px"
    b = VgaBench()
    b.tick(3300)
    low = sum(1 for e in b.expected[:1600] if not e["hsync"])
    act = sum(e["active"] for e in b.expected[:1600])
    assert low == 192 and act == 1280
    return b


def tc17():
    "One full VGA frame: 525 lines, VSYNC low 2 lines, frame_capture once at the start of blanking"
    b = VgaBench()
    b.tick(1600 * 525 + 3300)
    frame = b.expected[:1600 * 525]
    assert sum(1 for e in frame if not e["vsync"]) == 2 * 1600
    assert sum(e["frame_capture"] for e in frame) == 1
    # shortcut: fast-toggling x and pixel_ce left out because 843,300 clocks of them make the VCD too slow to convert; tc16 shows them.
    b.outputs = {k: VgaBench.outputs[k] for k in ("hsync", "vsync", "active", "frame_capture", "y")}
    b.top_signals_only = True
    return b


def tc18():
    "frame_snapshot holds its value while live data changes and updates only on capture"
    b = SnapshotBench()
    b.tick(2)
    for live, cap in [(3, 0), (5, 1), (9, 0), (12, 0), (7, 1), (1, 0), (2, 0), (15, 1), (4, 0)]:
        b.set(live_cursor=live, capture=cap)
        b.tick()
        if cap:
            assert b.saved == live
            b.set(capture=0)
            b.tick()
        else:
            b.tick()
    return b


def tc19():
    "Real top-level: VGA sync keeps running through SW9 reset; RGB stays black during HSYNC"
    b = TopBench()
    b.tick(1000)
    b.set(KEY=1)  # KEY1 start through the real debouncer
    b.tick(12)
    b.set(KEY=3)
    b.tick(600)
    b.set(SW=1 << 9)
    b.tick(1000)
    b.set(SW=0)
    b.tick(1000)
    return b


SCENARIOS = [tc01, tc02, tc03, tc04, tc05, tc06, tc07, tc08, tc09, tc10, tc11, tc12,
             tc13, tc14, tc15, tc16, tc17, tc18, tc19]
NAMES = {tc01: "shuffle_deck", tc02: "shuffle_seed", tc03: "cursor_reverse", tc04: "invalid_picks",
         tc05: "reveal_mismatch", tc06: "turns_scoring", tc07: "p1_wins", tc08: "p2_wins", tc09: "draw",
         tc10: "single_player_replay", tc11: "reset_all_states", tc12: "attempts_saturate",
         tc13: "debounce", tc14: "two_keys_sync", tc15: "reset_sync", tc16: "vga_line", tc17: "vga_frame",
         tc18: "snapshot", tc19: "top_level"}


def fname(fn):
    return f"{fn.__name__}_{NAMES[fn]}"


# ------------------------------------------------------------- VWF writer
def signal(name, width, direction, parent=""):
    kind = "SINGLE_BIT" if width == 1 else "BUS"
    lsb = -1 if width == 1 else 0
    return (f'SIGNAL("{name}")\n{{\n\tVALUE_TYPE = NINE_LEVEL_BIT;\n\tSIGNAL_TYPE = {kind};\n'
            f'\tWIDTH = {width};\n\tLSB_INDEX = {lsb};\n\tDIRECTION = {direction};\n\tPARENT = "{parent}";\n}}\n\n')


def transitions(name, levels):
    """levels = [(value, ns), ...] already merged."""
    body = "".join(f"\t\t\tLEVEL {v} FOR {d:.1f};\n" for v, d in levels)
    return (f'TRANSITION_LIST("{name}")\n{{\n\tNODE\n\t{{\n\t\tREPEAT = 1;\n\t\tNODE\n\t\t{{\n'
            f'\t\t\tREPEAT = 1;\n{body}\t\t}}\n\t}}\n}}\n\n')


def merge(values):
    out = []
    for v in values:
        if out and out[-1][0] == v:
            out[-1][1] += PERIOD
        else:
            out.append([v, PERIOD])
    return out


def settings(fn, b):
    """University VWF settings, with -voptargs=+acc because Questa 2025 rejects the default -novopt."""
    top = f"vwf_{b.block}"
    name = fname(fn)
    d = (ROOT / b.block).resolve().as_posix()
    tb = (f'quartus_eda --gen_testbench --tool=modelsim_oem --format=vhdl --write_settings_files=off {top} -c {top} '
          f'--vector_source="{d}/{name}.vwf" --testbench_file="{d}/simulation/qsim/{name}.vwf.vht"')
    net = ('quartus_eda --write_settings_files=off --simulation --functional={} --flatten_buses=off{} --tool=modelsim_oem '
           f'--format=vhdl --output_directory="{d}/simulation/qsim/" {top} -c {top}')
    libs = "-L fiftyfivenm -L altera -L altera_mf -L 220model -L sgate -L altera_lnsim"
    inner = "" if getattr(b, "top_signals_only", False) else f"vcd add -internal {top}_vhd_vec_tst/i1/*\n"
    body = (f"vcd file -direction {top}.msim.vcd\nvcd add -internal {top}_vhd_vec_tst/*\n"
            f"{inner}proc simTimestamp {{}} {{\n"
            '    echo "Simulation time: $::now ps"\n    if { [string equal running [runStatus]] } {\n'
            "        after 2500 simTimestamp\n    }\n}\nafter 2500 simTimestamp\nrun -all\nquit -f\n")
    start = f"onerror {{exit -code 1}}\nvlib work\nvcom -work work {top}.vho\nvcom -work work {name}.vwf.vht\n"
    return (f"/*<simulation_settings>\n<ftestbench_cmd>{tb}</ftestbench_cmd>\n<ttestbench_cmd>{tb}</ttestbench_cmd>\n"
            f"<fnetlist_cmd>{net.format('on', '')}</fnetlist_cmd>\n"
            f"<tnetlist_cmd>{net.format('off', ' --timescale=1ps')}</tnetlist_cmd>\n"
            f"<modelsim_script>{start}vsim -voptargs=+acc -c -t 1ps {libs} work.{top}_vhd_vec_tst\n{body}</modelsim_script>\n"
            f"<modelsim_script_timing>{start}vsim -voptargs=+acc -c -t 1ps -sdfmax {top}_vhd_vec_tst/i1={top}_vhd.sdo {libs} "
            f"work.{top}_vhd_vec_tst\n{body}</modelsim_script_timing>\n<hdl_lang>vhdl</hdl_lang>\n</simulation_settings>*/\n")


def write_vwf(fn, b):
    cycles = len(b.rows)
    end = cycles * PERIOD
    clk = "MAX10_CLK1_50" if b.block == "top" else "clk"
    sig, tr, disp = [], [], []
    index = [0]

    def line(channel, radix, level=0, children=None, parent=None):
        i = index[0]
        index[0] += 1
        text = (f'DISPLAY_LINE\n{{\n\tCHANNEL = "{channel}";\n\tEXPAND_STATUS = COLLAPSED;\n\tRADIX = {radix};\n'
                f'\tTREE_INDEX = {i};\n\tTREE_LEVEL = {level};\n')
        if parent is not None:
            text += f"\tPARENT = {parent};\n"
        if children:
            text += "\tCHILDREN = " + ", ".join(str(i + 1 + k) for k in range(children)) + ";\n"
        disp.append(text + "}\n\n")
        return i

    sig.append(signal(clk, 1, "INPUT"))
    tr.append(f'TRANSITION_LIST("{clk}")\n{{\n\tNODE\n\t{{\n\t\tREPEAT = 1;\n\t\tNODE\n\t\t{{\n'
              f'\t\t\tREPEAT = {cycles};\n\t\t\tLEVEL 0 FOR 10.0;\n\t\t\tLEVEL 1 FOR 10.0;\n\t\t}}\n\t}}\n}}\n\n')
    line(clk, "Binary")
    for direction, group in (("INPUT", b.inputs), ("OUTPUT", b.outputs)):
        for name, width in group.items():
            radix = b.radix.get(name, "Unsigned")
            sig.append(signal(name, width, direction))
            parent = line(name, radix, children=width if width > 1 else None)
            for bit in (range(width - 1, -1, -1) if width > 1 else [None]):
                ch = name if bit is None else f"{name}[{bit}]"
                if bit is not None:
                    sig.append(signal(ch, 1, direction, name))
                    line(ch, radix, level=1, parent=parent)
                if direction == "OUTPUT":
                    tr.append(transitions(ch, [("X", float(end))]))
                else:
                    shift = bit or 0
                    tr.append(transitions(ch, [(v, float(d)) for v, d in
                                               merge((r[name] >> shift) & 1 for r in b.rows)]))
    header = (settings(fn, b) + f"/*\n{fn.__doc__}\nGenerated by waveforms/gen_vwf.py\n*/\n\nHEADER\n{{\n\tVERSION = 1;\n\tTIME_UNIT = ns;\n"
              f"\tDATA_OFFSET = 0.0;\n\tDATA_DURATION = {end}.0;\n\tSIMULATION_TIME = 0.0;\n\tGRID_PHASE = 0.0;\n"
              f"\tGRID_PERIOD = 20.0;\n\tGRID_DUTY_CYCLE = 50;\n}}\n\n")
    out = header + "".join(sig) + "".join(tr) + "".join(disp) + "TIME_BAR\n{\n\tTIME = 0;\n\tMASTER = TRUE;\n}\n;\n"
    (ROOT / b.block / f"{fname(fn)}.vwf").write_text(out, newline="\r\n")
    return cycles


def write_project(block):
    d = ROOT / block
    top = f"vwf_{block}"
    (d / f"{top}.qpf").write_text(f'QUARTUS_VERSION = "25.1"\nPROJECT_REVISION = "{top}"\n')
    files = "".join(f"set_global_assignment -name VHDL_FILE ../../rtl/{f}.vhd\n" for f in RTL[block])
    (d / f"{top}.qsf").write_text(
        'set_global_assignment -name FAMILY "MAX 10"\n'
        "set_global_assignment -name DEVICE 10M50DAF484C7G\n"
        f"set_global_assignment -name TOP_LEVEL_ENTITY {top}\n"
        "set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files\n"
        "set_global_assignment -name VHDL_INPUT_VERSION VHDL_2008\n"
        f"{files}set_global_assignment -name VHDL_FILE {top}.vhd\n")


# ------------------------------------------------------------- VCD checker
def read_vcd(path, sample_times):
    """Return {name: [value at each sample time]} for the testbench's top scope."""
    ids, scope = {}, 0
    current, out = {}, {}
    idx = 0
    t = 0
    with open(path) as f:
        for raw in f:
            if raw.startswith("$scope"):
                scope += 1
            elif raw.startswith("$upscope"):
                scope -= 1
            elif raw.startswith("$var") and scope == 1:
                p = raw.split()
                # Questa dumps output buses as one scalar per bit: "name [3]".
                ids[p[3]] = p[4] + (p[5] if re.fullmatch(r"\[\d+\]", p[5]) else "")
            elif raw.startswith("$enddefinitions"):
                break
        out = {n: [] for n in ids.values()}
        for raw in f:
            c = raw[:1]
            if c == "#":
                t = int(raw[1:])
                while idx < len(sample_times) and sample_times[idx] < t:
                    for n in out:
                        out[n].append(current.get(n))
                    idx += 1
            elif c in "01xXzZ":
                k = raw[1:].strip()
                if k in ids:
                    current[ids[k]] = c
            elif c in "bB":
                v, k = raw[1:].split()
                if k in ids:
                    current[ids[k]] = v
    while idx < len(sample_times):
        for n in out:
            out[n].append(current.get(n))
        idx += 1
    buses = {}
    for n in out:
        m = re.fullmatch(r"(\w+)\[(\d+)\]", n)
        if m:
            buses.setdefault(m[1], {})[int(m[2])] = out[n]
    for name, bits in buses.items():
        cols = [bits[i] for i in sorted(bits, reverse=True)]
        out[name] = ["x" if None in vals else "".join(vals) for vals in zip(*cols)]
    return out


def to_int(v):
    return None if v is None or re.search("[xXzZ]", v) else int(v, 2)


def check_top(data):
    hs = [to_int(v) for v in data["VGA_HS"]]
    assert None not in hs[8:], "VGA_HS unknown after start-up"
    falls = [i for i in range(1, len(hs)) if hs[i - 1] == 1 and hs[i] == 0]
    rises = [i for i in range(1, len(hs)) if hs[i - 1] == 0 and hs[i] == 1]
    assert len(falls) >= 2, "VGA_HS did not toggle"
    assert all(b - a == 1600 for a, b in zip(falls, falls[1:])), "line period is not 800 pixels"
    assert all(r - f == 192 for f, r in zip(falls, [r for r in rises if r > falls[0]])), "HSYNC is not 96 pixels"
    for ch in ("VGA_R", "VGA_G", "VGA_B"):
        assert all(to_int(data[ch][i]) == 0 for i, h in enumerate(hs) if h == 0), f"{ch} not black in HSYNC"


def check():
    failures = 0
    for fn in SCENARIOS:
        if len(sys.argv) > 2 and fn.__name__ not in sys.argv[2:]:
            continue
        b = fn()
        name = fname(fn)
        vcds = sorted((ROOT / b.block / "simulation" / "qsim").glob(f"{name}*.vcd"))
        if not vcds:
            print(f"MISSING {name}: no VCD")
            failures += 1
            continue
        cycles = len(b.rows)
        data = read_vcd(vcds[-1], [(k * PERIOD + 16) * 1000 for k in range(cycles)])
        try:
            if b.block == "top":
                check_top(data)
            else:
                for k, exp in enumerate(b.expected):
                    for sig in b.outputs:
                        val = exp[sig]
                        got = to_int(data[sig][k])
                        assert got == val, f"cycle {k}: {sig} = {data[sig][k]}, expected {val}"
            print(f"PASS {name} ({cycles} clocks)")
        except AssertionError as e:
            print(f"FAIL {name}: {e}")
            failures += 1
    return failures


def main():
    if "--check" in sys.argv:
        sys.exit(1 if check() else 0)
    for block in RTL:
        (ROOT / block).mkdir(exist_ok=True)
        write_project(block)
    for fn in SCENARIOS:
        b = fn()
        print(f"{b.block:18} {fname(fn):32} {write_vwf(fn, b):7} clocks  {fn.__doc__}")


if __name__ == "__main__":
    main()
