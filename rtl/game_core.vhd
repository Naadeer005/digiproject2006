library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.game_pkg.all;

entity game_core is
  generic (REVEAL_CYCLES : positive := 50_000_000);
  port (
    clk, reset_game, next_press, open_press, mode_sync : in std_logic;
    game : out view_t
  );
end;

architecture rtl of game_core is
  signal v : view_t := INITIAL_VIEW;
  signal reveal_count : natural range 0 to REVEAL_CYCLES-1 := 0;
  signal shuffle_i : natural range 1 to 15 := 15;
  signal seed_counter : unsigned(15 downto 0) := x"ACE1";
  signal rng : unsigned(15 downto 0) := x"ACE1";
  signal remainder_value : natural range 0 to 15 := 0;
  signal bit_step : natural range 0 to 16 := 0;
begin
  game <= v;
  process(clk)
    variable reduced : natural range 0 to 31;
  begin
    if rising_edge(clk) then
      -- Free running even during reset; the player's start timing varies seed.
      seed_counter <= seed_counter + 1;
      if reset_game = '1' then
        v <= INITIAL_VIEW;
        reveal_count <= 0;
        shuffle_i <= 15;
        rng <= x"ACE1";
        remainder_value <= 0;
        bit_step <= 0;
      else
        case v.state is
          when READY =>
            v.two_players <= mode_sync;
            if open_press = '1' then
              v <= INITIAL_VIEW;
              v.two_players <= mode_sync;
              v.state <= SHUFFLE;
              shuffle_i <= 15;
              remainder_value <= 0;
              bit_step <= 0;
              if seed_counter = 0 then rng <= x"ACE1";
              else rng <= seed_counter; end if;
            end if;
          when SHUFFLE =>
            -- Bit-serial rng mod (i+1): one small compare/subtract per clock,
            -- then a swap. 15 * 17 clocks = 5.1 us at 50 MHz.
            if bit_step < 16 then
              reduced := remainder_value*2;
              if rng(15-bit_step) = '1' then reduced := reduced+1; end if;
              if reduced >= shuffle_i+1 then reduced := reduced-(shuffle_i+1); end if;
              remainder_value <= reduced;
              bit_step <= bit_step+1;
            else
              v.cards(shuffle_i) <= v.cards(remainder_value);
              v.cards(remainder_value) <= v.cards(shuffle_i);
              rng <= rng(14 downto 0) & (rng(15) xor rng(13) xor rng(12) xor rng(10));
              remainder_value <= 0;
              bit_step <= 0;
              if shuffle_i = 1 then v.state <= PICK_FIRST;
              else shuffle_i <= shuffle_i-1; end if;
            end if;
          when PICK_FIRST | PICK_SECOND =>
            -- Open takes priority even when the selected card is invalid.
            if open_press = '1' then
              if v.matched(v.cursor) = '0' then
                if v.state = PICK_FIRST then
                  v.first_card <= v.cursor;
                  v.state <= PICK_SECOND;
                elsif v.cursor /= v.first_card then
                  v.second_card <= v.cursor;
                  if v.attempts < 999 then v.attempts <= v.attempts+1; end if;
                  reveal_count <= 0;
                  v.state <= REVEAL;
                end if;
              end if;
            elsif next_press = '1' then
              if v.cursor = 15 then v.cursor <= 0;
              else v.cursor <= v.cursor+1; end if;
            end if;
          when REVEAL =>
            if reveal_count = REVEAL_CYCLES-1 then v.state <= CHECK;
            else reveal_count <= reveal_count+1; end if;
          when CHECK =>
            if v.cards(v.first_card) = v.cards(v.second_card) then
              v.matched(v.first_card) <= '1';
              v.matched(v.second_card) <= '1';
              v.pairs <= v.pairs+1;
              if v.player = '0' then v.score1 <= v.score1+1;
              else v.score2 <= v.score2+1; end if;
              if v.pairs = 7 then v.state <= GAME_OVER;
              else v.state <= PICK_FIRST; end if;
            else
              if v.two_players = '1' then v.player <= not v.player; end if;
              v.state <= PICK_FIRST;
            end if;
          when GAME_OVER =>
            if open_press = '1' then v.state <= READY; end if;
        end case;
      end if;
    end if;
  end process;
end;
