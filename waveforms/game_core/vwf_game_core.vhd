-- VWF wrapper: exposes game_core's view_t record as plain buses and shortens
-- the reveal time, because University VWF cannot override generics or show records.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.game_pkg.all;

entity vwf_game_core is
  port (
    clk, reset_game, next_press, open_press, mode_sync, reverse_sync : in std_logic;
    state : out std_logic_vector(2 downto 0); -- 0 READY 1 SHUFFLE 2 PICK_FIRST 3 PICK_SECOND 4 REVEAL 5 CHECK 6 GAME_OVER
    cursor, first_card, second_card : out std_logic_vector(3 downto 0);
    card_at_cursor : out std_logic_vector(2 downto 0);
    matched : out std_logic_vector(15 downto 0);
    two_players, player, reverse : out std_logic;
    score1, score2, pairs : out std_logic_vector(3 downto 0);
    attempts : out std_logic_vector(9 downto 0)
  );
end;

architecture rtl of vwf_game_core is
  signal g : view_t;
begin
  core : entity work.game_core
    generic map (REVEAL_CYCLES => 8)
    port map (clk, reset_game, next_press, open_press, mode_sync, g, reverse_sync);
  state <= std_logic_vector(to_unsigned(state_t'pos(g.state), 3));
  cursor <= std_logic_vector(to_unsigned(g.cursor, 4));
  first_card <= std_logic_vector(to_unsigned(g.first_card, 4));
  second_card <= std_logic_vector(to_unsigned(g.second_card, 4));
  card_at_cursor <= std_logic_vector(to_unsigned(g.cards(g.cursor), 3));
  matched <= g.matched;
  two_players <= g.two_players;
  player <= g.player;
  reverse <= g.reverse;
  score1 <= std_logic_vector(to_unsigned(g.score1, 4));
  score2 <= std_logic_vector(to_unsigned(g.score2, 4));
  pairs <= std_logic_vector(to_unsigned(g.pairs, 4));
  attempts <= std_logic_vector(to_unsigned(g.attempts, 10));
end;
