-- VWF wrapper: exposes vga_timing's natural-range x/y as plain buses.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vwf_vga_timing is
  port (
    clk, reset : in std_logic;
    pixel_ce, active, hsync, vsync, frame_capture : out std_logic;
    x, y : out std_logic_vector(9 downto 0)
  );
end;

architecture rtl of vwf_vga_timing is
  signal xi : natural range 0 to 799;
  signal yi : natural range 0 to 524;
begin
  dut : entity work.vga_timing
    port map (clk, reset, pixel_ce, xi, yi, active, hsync, vsync, frame_capture);
  x <= std_logic_vector(to_unsigned(xi, 10));
  y <= std_logic_vector(to_unsigned(yi, 10));
end;
