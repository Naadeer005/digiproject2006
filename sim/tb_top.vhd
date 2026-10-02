library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
entity tb_top is end;
architecture test of tb_top is
  signal clk : std_logic := '0';
  signal keys : std_logic_vector(1 downto 0) := "11";
  signal switches : std_logic_vector(9 downto 0) := (others => '0');
  signal r,g,b : std_logic_vector(3 downto 0);
  signal hs,vs : std_logic;
begin
  clk <= not clk after 10 ns;
  dut : entity work.top generic map(4,8) port map(clk,keys,switches,r,g,b,hs,vs);
  process
  begin
    wait for 200 ns; keys(1) <= '0'; wait for 300 ns; keys(1) <= '1';
    -- Reset while raster is running; sync must continue without interruption.
    wait for 34 ms; switches(9) <= '1'; wait;
  end process;
  process
    variable expected_hs,expected_vs : std_logic;
    variable previous_rgb : std_logic_vector(11 downto 0);
  begin
    -- One renderer pixel of latency: first valid pixel on fourth clock edge.
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    for frame in 1 to 3 loop
      for row in 0 to 524 loop
        for col in 0 to 799 loop
          wait until rising_edge(clk); wait for 1 ns;
          expected_hs := '1'; expected_vs := '1';
          if col >= 656 and col < 752 then expected_hs := '0'; end if;
          if row >= 490 and row < 492 then expected_vs := '0'; end if;
          assert hs = expected_hs and vs = expected_vs report "Top-level sync misaligned" severity failure;
          if col >= 640 or row >= 480 then
            assert (r & g & b) = x"000" report "Top-level blanking misaligned" severity failure;
          end if;
          if col = 144 and row = 80 and frame = 2 then
            assert (r & g & b) = x"FF3" report "Start button did not reach displayed game" severity failure;
          end if;
          previous_rgb := r & g & b;
          wait until rising_edge(clk); wait for 1 ns;
          assert (r & g & b) = previous_rgb and hs = expected_hs and vs = expected_vs
            report "Outputs changed between pixel enables" severity failure;
        end loop;
      end loop;
    end loop;
    report "PASS tb_top: registered RGB/sync, start button, three frames, continuous sync during reset";
    finish;
  end process;
  process begin wait for 100 ms; assert false report "Top test timeout" severity failure; end process;
end;
