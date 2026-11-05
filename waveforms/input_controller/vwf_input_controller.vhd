-- VWF wrapper: shortens debounce to 4 clocks (hardware uses 1,000,000).
library ieee;
use ieee.std_logic_1164.all;

entity vwf_input_controller is
  port (
    clk : in std_logic;
    key_n : in std_logic_vector(1 downto 0);
    mode_switch, reset_switch, reverse_switch : in std_logic;
    next_press, open_press, mode_sync, reset_game, reverse_sync : out std_logic
  );
end;

architecture rtl of vwf_input_controller is
begin
  dut : entity work.input_controller
    generic map (DEBOUNCE_CYCLES => 4)
    port map (clk, key_n, mode_switch, reset_switch, next_press, open_press,
              mode_sync, reset_game, reverse_switch, reverse_sync);
end;
