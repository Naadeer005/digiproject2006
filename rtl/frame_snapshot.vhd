library ieee;
use ieee.std_logic_1164.all;
use work.game_pkg.all;

entity frame_snapshot is
  port (clk, capture : in std_logic; live_game : in view_t; frame_game : out view_t);
end;
architecture rtl of frame_snapshot is
  signal saved : view_t := INITIAL_VIEW;
begin
  frame_game <= saved;
  process(clk)
  begin
    if rising_edge(clk) then
      if capture = '1' then saved <= live_game; end if;
    end if;
  end process;
end;
