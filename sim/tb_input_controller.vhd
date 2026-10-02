library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
entity tb_input_controller is end;
architecture test of tb_input_controller is
  signal clk : std_logic := '0';
  signal keys : std_logic_vector(1 downto 0) := "11";
  signal mode_sw, reset_sw, move_p, open_p, mode_s, rst : std_logic := '0';
  signal moves, opens : natural := 0;
begin
  clk <= not clk after 10 ns;
  dut : entity work.input_controller generic map(4) port map(clk,keys,mode_sw,reset_sw,move_p,open_p,mode_s,rst);
  process(clk)
  begin
    if rising_edge(clk) then
      if move_p = '1' then moves <= moves+1; end if;
      if open_p = '1' then opens <= opens+1; end if;
    end if;
  end process;
  process
    procedure tick(n : positive := 1) is
    begin for i in 1 to n loop wait until rising_edge(clk); wait for 1 ns; end loop; end;
  begin
    tick(10); assert rst = '0' report "Power-on reset failed to release" severity failure;
    keys(0) <= '0'; tick; keys(0) <= '1'; tick;
    keys(0) <= '0'; tick(2); keys(0) <= '1'; tick(10);
    assert moves = 0 report "Bounce caused a press" severity failure;
    keys(0) <= '0'; tick(12);
    assert moves = 1 report "Stable press missing" severity failure;
    tick(30); assert moves = 1 report "Held key repeated" severity failure;
    keys(0) <= '1'; tick; keys(0) <= '0'; tick(12);
    assert moves = 1 report "Release bounce repeated" severity failure;
    keys <= "11"; tick(12); keys <= "00"; tick(12);
    assert moves = 2 and opens = 1 report "Simultaneous button pulses missing" severity failure;
    mode_sw <= '1'; tick(3); assert mode_s = '1' severity failure;
    reset_sw <= '1'; wait for 1 ns;
    assert rst = '1' report "Reset did not assert asynchronously" severity failure;
    tick(10); keys <= "11"; reset_sw <= '0';
    tick; assert rst = '1' report "Reset release not synchronized" severity failure;
    tick; assert rst = '0' report "Reset release failed" severity failure;
    tick(10);
    assert moves = 2 and opens = 1 report "Reset generated button pulses" severity failure;
    report "PASS tb_input_controller: synchronization, bounce, holds, simultaneous keys, reset";
    finish;
  end process;
end;
