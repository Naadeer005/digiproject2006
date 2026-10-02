library ieee;
use ieee.std_logic_1164.all;

entity input_controller is
  generic (DEBOUNCE_CYCLES : positive := 1_000_000);
  port (
    clk : in std_logic;
    key_n : in std_logic_vector(1 downto 0);
    mode_switch, reset_switch : in std_logic;
    next_press, open_press, mode_sync, reset_game : out std_logic
  );
end;

architecture rtl of input_controller is
  signal key_meta, key_sync, stable : std_logic_vector(1 downto 0) := "11";
  signal mode_meta, mode_reg : std_logic := '0';
  -- Asynchronous assertion, two-clock synchronous reset release. Initial high
  -- also gives all modules a deterministic power-on reset after configuration.
  signal reset_pipe : std_logic_vector(1 downto 0) := "11";
  type counts_t is array(0 to 1) of natural range 0 to DEBOUNCE_CYCLES-1;
  signal counts : counts_t := (others => 0);
  signal pulses : std_logic_vector(1 downto 0) := "00";
begin
  process(clk, reset_switch)
  begin
    if reset_switch = '1' then
      reset_pipe <= "11";
    elsif rising_edge(clk) then
      reset_pipe <= reset_pipe(0) & '0';
    end if;
  end process;
  reset_game <= reset_pipe(1);
  mode_sync <= mode_reg;
  next_press <= pulses(0);
  open_press <= pulses(1);

  process(clk)
  begin
    if rising_edge(clk) then
      key_meta <= key_n;
      key_sync <= key_meta;
      mode_meta <= mode_switch;
      mode_reg <= mode_meta;
      pulses <= "00";
      if reset_pipe(1) = '1' then
        stable <= "11";
        counts <= (others => 0);
      else
        for i in 0 to 1 loop
          if key_sync(i) = stable(i) then
            counts(i) <= 0;
          elsif counts(i) = DEBOUNCE_CYCLES-1 then
            stable(i) <= key_sync(i);
            counts(i) <= 0;
            if key_sync(i) = '0' then pulses(i) <= '1'; end if;
          else
            counts(i) <= counts(i)+1;
          end if;
        end loop;
      end if;
    end if;
  end process;
end;
