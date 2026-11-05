# University VWF waveforms

Functional simulations run in the Quartus Prime Lite 25.1 Simulation Waveform Editor (University Program VWF) on device 10M50DAF484C7G. Each `.vwf` sits next to its Quartus project and each screenshot is in [png/](png/). `_zoom` images show the part after the shuffle at a readable scale.

## Why there are wrappers

University VWF only drives top-level pins and cannot override generics. So each block has a small `vwf_*` wrapper as top-level entity, in its own project. The wrappers expose internal values as plain buses and shorten debounce to 4 clocks and reveal to 8 clocks (hardware: 1,000,000 and 50,000,000), matching the testbenches in `sim/`. `rtl/` and `memory_match.qsf` are unchanged.

## Reading the waveforms

Clock period is 20 ns. Inputs change on falling edges.

`state`: 0 READY, 1 SHUFFLE, 2 PICK_FIRST, 3 PICK_SECOND, 4 REVEAL, 5 CHECK, 6 GAME_OVER

## Test cases

| # | Project | What it shows | Files |
|---|---------|---------------|-------|
| 01 | game_core | READY, SHUFFLE, PICK_FIRST; walking 16 cards shows each ID twice | [full](png/tc01_shuffle_deck.png), [zoom](png/tc01_shuffle_deck_zoom.png) |
| 02 | game_core | Starting 5 clocks later gives a different deck | [full](png/tc02_shuffle_seed.png), [zoom](png/tc02_shuffle_seed_zoom.png) |
| 03 | game_core | Cursor wraps 15 to 0; SW8 reverse goes 0, 15, 14; forward resumes | [full](png/tc03_cursor_reverse.png), [zoom](png/tc03_cursor_reverse_zoom.png) |
| 04 | game_core | KEY1 beats KEY0; same card and matched card cannot be opened | [full](png/tc04_invalid_picks.png), [zoom](png/tc04_invalid_picks_zoom.png) |
| 05 | game_core | Reveal lasts 8 clocks and ignores keys; mismatch closes cards; mode locked during play | [full](png/tc05_reveal_mismatch.png), [zoom](png/tc05_reveal_mismatch_zoom.png) |
| 06 | game_core | 2 players: mismatch switches turn; match scores and keeps the turn | [full](png/tc06_turns_scoring.png), [zoom](png/tc06_turns_scoring_zoom.png) |
| 07 | game_core | Player 1 wins 8-0 | [full](png/tc07_p1_wins.png), [zoom](png/tc07_p1_wins_zoom.png) |
| 08 | game_core | Player 2 wins 8-0 | [full](png/tc08_p2_wins.png), [zoom](png/tc08_p2_wins_zoom.png) |
| 09 | game_core | Draw 4-4 | [full](png/tc09_draw.png), [zoom](png/tc09_draw_zoom.png) |
| 10 | game_core | 1 player: full game in 9 attempts; replay returns to a clean READY | [full](png/tc10_single_player_replay.png), [zoom](png/tc10_single_player_replay_zoom.png) |
| 11 | game_core | Reset clears the game from all 7 states | [full](png/tc11_reset_all_states.png), [READY to PICK_SECOND](png/tc11_reset_all_states_zoom2.png), [REVEAL/CHECK](png/tc11_reset_all_states_zoom1.png), [GAME_OVER](png/tc11_reset_all_states_zoom3.png) |
| 12 | game_core | 1,002 real mismatches: `attempts` stops at 999, score stays 0 | [full](png/tc12_attempts_saturate.png), [zoom](png/tc12_attempts_saturate_zoom.png) |
| 13 | input_controller | Press and release bounce ignored; one pulse per press; held key does not repeat | [full](png/tc13_debounce.png) |
| 14 | input_controller | Both keys together give one pulse each; SW0 and SW8 synchronizers | [full](png/tc14_two_keys_sync.png) |
| 15 | input_controller | Power-on reset; SW9 asserts immediately, releases after 2 clocks; no false pulse | [full](png/tc15_reset_sync.png) |
| 16 | vga_timing | Two lines: 800 pixels, active 640, HSYNC low 96, pixel_ce every 2 clocks | [full](png/tc16_vga_line.png), [zoom](png/tc16_vga_line_zoom.png) |
| 17 | vga_timing | One full frame: 525 lines, VSYNC low 2 lines, one frame_capture. **No screenshot**, see below | checked by script only |
| 18 | frame_snapshot | Output holds while live data changes; updates only on capture | [full](png/tc18_snapshot.png) |
| 19 | top | Real top-level: HSYNC keeps running through SW9 reset; RGB black during sync | [full](png/tc19_top_level.png) |

## Limits

- **tc17 has no University VWF capture.** Running it from the Waveform Editor crashed Quartus, so do not run `tc17_vga_frame.vwf` there. A full frame is 16.9 ms, and the generated testbench's time value (`16866000000 ps`) overflows a 32-bit integer past about 2.1 ms. `run_all.ps1` rewrites that value in microseconds and checks the frame in Questa, using only hsync, vsync, active, frame_capture and y. VSYNC therefore has no waveform image here.
- tc19 covers less than `sim/tb_top.vhd`: two lines rather than three full frames, and no check that a key press reaches the screen.
- These are functional simulations. They do not include timing delays and do not replace testing on the board.

## Re-running

`gen_vwf.py` models each block cycle by cycle, writes the `.vwf` files, and compares simulated outputs with the model. tc19 is checked with rules on the sync and RGB signals, not a model. `capture.ps1` saves the open result window to `png/`.

```bash
python waveforms/gen_vwf.py
```

```bash
powershell -File waveforms/run_all.ps1
```

To run one by hand: open the block's `.qpf`, run Analysis & Synthesis, open the `.vwf`, then choose Simulation > Run Functional Simulation.

The `.vwf` files already use `-voptargs=+acc`, because the default `-novopt` makes Questa 2025.2 stop with an error. They store absolute paths for `D:/code/2026/labdigiporg/digiproject2006`, so run `gen_vwf.py` again if the folder moves.
