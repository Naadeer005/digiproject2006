library ieee;
use ieee.std_logic_1164.all;
use work.game_pkg.all;

entity top is
  generic (
    DEBOUNCE_CYCLES : positive := 1_000_000;
    REVEAL_CYCLES : positive := 50_000_000
  );
  port (
    MAX10_CLK1_50 : in std_logic;
    KEY : in std_logic_vector(1 downto 0);
    SW : in std_logic_vector(9 downto 0);
    VGA_R, VGA_G, VGA_B : out std_logic_vector(3 downto 0);
    VGA_HS, VGA_VS : out std_logic
  );
end;

architecture rtl of top is
  signal next_press, open_press, mode_sync, reset_game : std_logic;
  signal pixel_ce, active, hs, vs, capture : std_logic;
  signal x : natural range 0 to 799;
  signal y : natural range 0 to 524;
  signal live_game, frame_game : view_t := INITIAL_VIEW;
  signal rgb : rgb_t;
  signal hs_delayed, vs_delayed : std_logic := '1';
begin
  inputs : entity work.input_controller
    generic map (DEBOUNCE_CYCLES => DEBOUNCE_CYCLES)
    port map (MAX10_CLK1_50, KEY, SW(0), SW(9), next_press, open_press, mode_sync, reset_game);
  core : entity work.game_core
    generic map (REVEAL_CYCLES => REVEAL_CYCLES)
    port map (MAX10_CLK1_50, reset_game, next_press, open_press, mode_sync, live_game);
  -- Keep sync running while SW9 is held. FPGA register initial values start
  -- the raster at (0,0); game reset never tears or stops the VGA signal.
  timing : entity work.vga_timing
    port map (MAX10_CLK1_50, '0', pixel_ce, x, y, active, hs, vs, capture);
  snapshot : entity work.frame_snapshot
    port map (MAX10_CLK1_50, capture, live_game, frame_game);
  drawing : entity work.renderer port map (MAX10_CLK1_50, pixel_ce, x, y, active, frame_game, rgb);
  process(MAX10_CLK1_50)
  begin
    if rising_edge(MAX10_CLK1_50) then
      if pixel_ce = '1' then
        -- Register color and sync together, preserving their pixel alignment.
        VGA_R <= rgb(11 downto 8); VGA_G <= rgb(7 downto 4); VGA_B <= rgb(3 downto 0);
        hs_delayed <= hs; vs_delayed <= vs;
        VGA_HS <= hs_delayed; VGA_VS <= vs_delayed;
      end if;
    end if;
  end process;
end;
