library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package game_pkg is
  type state_t is (READY, SHUFFLE, PICK_FIRST, PICK_SECOND, REVEAL, CHECK, GAME_OVER);
  subtype card_id_t is natural range 0 to 7;
  subtype position_t is natural range 0 to 15;
  type deck_t is array (0 to 15) of card_id_t;
  type view_t is record
    state : state_t;
    cards : deck_t;
    matched : std_logic_vector(15 downto 0);
    cursor, first_card, second_card : position_t;
    two_players, player : std_logic;
    score1, score2, pairs : natural range 0 to 8;
    attempts : natural range 0 to 999;
  end record;
  constant INITIAL_DECK : deck_t := (0,1,2,3,4,5,6,7,0,1,2,3,4,5,6,7);
  constant INITIAL_VIEW : view_t := (
    READY, INITIAL_DECK, (others => '0'), 0, 0, 0, '0', '0', 0, 0, 0, 0);
  subtype rgb_t is std_logic_vector(11 downto 0);
  function face_up(v : view_t; i : position_t) return boolean;
  function digit(n : natural) return character;
end package;

package body game_pkg is
  function face_up(v : view_t; i : position_t) return boolean is
  begin
    return v.matched(i) = '1' or
      ((v.state = PICK_SECOND or v.state = REVEAL or v.state = CHECK) and i = v.first_card) or
      ((v.state = REVEAL or v.state = CHECK) and i = v.second_card);
  end;
  function digit(n : natural) return character is
  begin
    return character'val(character'pos('0') + (n mod 10));
  end;
end package body;
