-- VWF wrapper: drives one view_t field (cursor) through frame_snapshot to show hold/capture.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.game_pkg.all;

entity vwf_frame_snapshot is
  port (
    clk, capture : in std_logic;
    live_cursor : in std_logic_vector(3 downto 0);
    frame_cursor : out std_logic_vector(3 downto 0)
  );
end;

architecture rtl of vwf_frame_snapshot is
  signal live, frame : view_t := INITIAL_VIEW;
begin
  process(all)
  begin
    live <= INITIAL_VIEW;
    live.cursor <= to_integer(unsigned(live_cursor));
  end process;
  dut : entity work.frame_snapshot port map (clk, capture, live, frame);
  frame_cursor <= std_logic_vector(to_unsigned(frame.cursor, 4));
end;
