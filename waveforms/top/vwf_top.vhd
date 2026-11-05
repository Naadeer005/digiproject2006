-- VWF wrapper: the real top-level with short debounce/reveal times, same pins.
library ieee;
use ieee.std_logic_1164.all;

entity vwf_top is
  port (
    MAX10_CLK1_50 : in std_logic;
    KEY : in std_logic_vector(1 downto 0);
    SW : in std_logic_vector(9 downto 0);
    VGA_R, VGA_G, VGA_B : out std_logic_vector(3 downto 0);
    VGA_HS, VGA_VS : out std_logic
  );
end;

architecture rtl of vwf_top is
begin
  dut : entity work.top
    generic map (DEBOUNCE_CYCLES => 4, REVEAL_CYCLES => 8)
    port map (MAX10_CLK1_50, KEY, SW, VGA_R, VGA_G, VGA_B, VGA_HS, VGA_VS);
end;
