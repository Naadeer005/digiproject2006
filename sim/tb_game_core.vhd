library ieee;
use ieee.std_logic_1164.all;
use work.game_pkg.all;
use std.env.all;

entity tb_game_core is end;
architecture test of tb_game_core is
  constant HOLD_CYCLES : positive := 8;
  signal clk : std_logic := '0';
  signal rst, move_key, open_key, mode : std_logic := '0';
  signal g : view_t;
begin
  clk <= not clk after 10 ns;
  dut : entity work.game_core generic map(HOLD_CYCLES) port map(clk,rst,move_key,open_key,mode,g);
  process
    type histogram_t is array(0 to 7) of natural;
    type coverage_t is array(state_t) of boolean;
    variable reset_coverage : coverage_t := (others => false);
    variable histogram : histogram_t;
    variable old_deck : deck_t;
    variable varied : boolean := false;
    variable a,b,c : position_t;
    variable old_player : std_logic;
    variable old_attempts : natural;
    procedure tick(n : positive := 1) is
    begin
      for i in 1 to n loop wait until rising_edge(clk); wait for 1 ns; end loop;
    end;
    procedure reset_now is
    begin
      reset_coverage(g.state) := true;
      rst <= '1'; tick; rst <= '0'; tick;
      assert g.state = READY and g.matched = x"0000" and g.pairs = 0 and
        g.score1 = 0 and g.score2 = 0 and g.attempts = 0 and g.cursor = 0
        report "Reset did not clear the game" severity failure;
    end;
    procedure press is
    begin open_key <= '1'; tick; open_key <= '0'; tick; end;
    procedure start_game(m : std_logic) is
    begin
      reset_now; mode <= m; tick; press;
      for i in 1 to 260 loop exit when g.state = PICK_FIRST; tick; end loop;
      assert g.state = PICK_FIRST and g.two_players = m report "Start/shuffle failed" severity failure;
      histogram := (others => 0);
      for i in 0 to 15 loop histogram(g.cards(i)) := histogram(g.cards(i))+1; end loop;
      for i in 0 to 7 loop assert histogram(i) = 2 report "Shuffle lost or duplicated a card" severity failure; end loop;
    end;
    procedure go_to(index : position_t) is
    begin
      for i in 1 to 16 loop
        exit when g.cursor = index;
        move_key <= '1'; tick; move_key <= '0'; tick;
      end loop;
      assert g.cursor = index report "Cursor navigation failed" severity failure;
    end;
    procedure find_pair(id : card_id_t; variable first,second : out position_t) is
      variable found : boolean := false;
    begin
      first := 0; second := 0;
      for i in 0 to 15 loop
        if g.cards(i) = id then
          if not found then first := i; found := true; else second := i; end if;
        end if;
      end loop;
    end;
    procedure resolve_pair(first,second : position_t) is
      variable attempts_before : natural;
    begin
      go_to(first); press;
      assert g.state = PICK_SECOND and face_up(g,first) report "First card not revealed" severity failure;
      go_to(second);
      attempts_before := g.attempts;
      open_key <= '1'; tick; open_key <= '0';
      assert g.state = REVEAL and face_up(g,first) and face_up(g,second)
        report "Second card not revealed" severity failure;
      if attempts_before < 999 then
        assert g.attempts = attempts_before+1 report "Attempt counter wrong" severity failure;
      else assert g.attempts = 999 report "Attempt counter did not saturate" severity failure; end if;
      move_key <= '1'; open_key <= '1';
      for i in 1 to HOLD_CYCLES-1 loop
        tick;
        assert g.state = REVEAL and g.cursor = second report "Reveal ended early or accepted input" severity failure;
      end loop;
      tick;
      assert g.state = CHECK report "Reveal duration incorrect" severity failure;
      move_key <= '0'; open_key <= '0'; tick;
      assert g.state = PICK_FIRST or g.state = GAME_OVER report "CHECK did not resolve" severity failure;
    end;
    procedure win_pair(id : card_id_t) is
    begin
      find_pair(id,a,b); old_player := g.player;
      resolve_pair(a,b);
      assert g.matched(a) = '1' and g.matched(b) = '1' and g.player = old_player
        report "Match not retained or changed turn" severity failure;
    end;
    procedure miss_pair(id1,id2 : card_id_t) is
    begin
      find_pair(id1,a,b); find_pair(id2,c,b);
      old_player := g.player;
      resolve_pair(a,c);
      assert not face_up(g,a) and not face_up(g,c) report "Mismatch remained open" severity failure;
      if g.two_players = '1' then assert g.player /= old_player report "Mismatch did not switch turn" severity failure;
      else assert g.player = '0' report "Single player changed turn" severity failure; end if;
    end;
  begin
    tick; start_game('0'); old_deck := g.cards;
    for seed in 1 to 12 loop
      tick(seed); start_game('0');
      if g.cards /= old_deck then varied := true; end if;
    end loop;
    assert varied report "Different start times never changed the deck" severity failure;
    go_to(15); move_key <= '1'; tick; move_key <= '0'; tick;
    assert g.cursor = 0 report "Cursor did not wrap" severity failure;
    move_key <= '1'; open_key <= '1'; tick; move_key <= '0'; open_key <= '0'; tick;
    assert g.state = PICK_SECOND and g.first_card = 0 and g.cursor = 0
      report "Open did not take priority" severity failure;
    press;
    assert g.state = PICK_SECOND and g.attempts = 0 report "Same card accepted twice" severity failure;
    reset_now; -- PICK_SECOND reset
    start_game('0'); reset_now; -- PICK_FIRST reset
    open_key <= '1'; tick; open_key <= '0';
    assert g.state = SHUFFLE severity failure;
    reset_now;
    start_game('0'); go_to(0); press; go_to(1); open_key <= '1'; tick; open_key <= '0';
    reset_now; -- REVEAL reset
    start_game('0'); go_to(0); press; go_to(1); open_key <= '1'; tick; open_key <= '0';
    tick(HOLD_CYCLES); assert g.state = CHECK severity failure; reset_now;

    start_game('0'); mode <= '1'; tick(4);
    assert g.two_players = '0' report "Mode changed during play" severity failure;
    miss_pair(0,1);
    for id in 0 to 7 loop
      win_pair(id);
      assert g.score1 = id+1 and g.score2 = 0 report "Score increment incorrect" severity failure;
      if id = 0 then
        go_to(a); old_attempts := g.attempts; press;
        assert g.state = PICK_FIRST and g.attempts = old_attempts report "Matched card accepted" severity failure;
      end if;
    end loop;
    assert g.state = GAME_OVER and g.score1 = 8 and g.pairs = 8 and g.attempts = 9
      report "Final pair/score wrong" severity failure;
    tick(5); assert g.score1 = 8 severity failure;
    press; assert g.state = READY report "Replay did not return to READY" severity failure;

    start_game('1');
    for id in 0 to 3 loop win_pair(id); end loop;
    miss_pair(4,5);
    for id in 4 to 7 loop win_pair(id); end loop;
    assert g.state = GAME_OVER and g.score1 = 4 and g.score2 = 4 report "Draw game failed" severity failure;
    reset_now; -- GAME_OVER reset
    start_game('1'); miss_pair(0,1);
    for id in 0 to 7 loop win_pair(id); end loop;
    assert g.state = GAME_OVER and g.score2 = 8 and g.score1 = 0 report "Player 2 win failed" severity failure;
    start_game('1');
    for id in 0 to 7 loop win_pair(id); end loop;
    assert g.state = GAME_OVER and g.score1 = 8 and g.score2 = 0 report "Player 1 win failed" severity failure;

    start_game('0');
    for attempt in 1 to 1002 loop miss_pair(0,1); end loop;
    assert g.attempts = 999 and g.score1 = 0 report "Saturation changed score or wrapped" severity failure;
    for s in state_t loop assert reset_coverage(s) report "Missing reset coverage for " & state_t'image(s) severity failure; end loop;
    report "PASS tb_game_core: shuffle, all FSM resets, rules, both winners, draw, replay, saturation";
    finish;
  end process;
end;
