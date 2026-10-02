library ieee;
use ieee.std_logic_1164.all;
use work.game_pkg.all;
use work.font_pkg.all;

entity renderer is
  port (
    clk, pixel_ce : in std_logic;
    x : in natural range 0 to 799;
    y : in natural range 0 to 524;
    active : in std_logic;
    game : in view_t;
    rgb : out rgb_t
  );
end;

architecture rtl of renderer is
  type palette_t is array(0 to 7) of rgb_t;
  constant PALETTE : palette_t := (x"B34", x"276", x"258", x"735", x"853", x"368", x"647", x"567");
  constant TITLE : string := "MEMORY MATCH";
  constant CONTROLS : string := "KEY0 NEXT   KEY1 OPEN   SW9 RESET";
  signal glyph_d, glyph_q : character := ' ';
  signal gx_d, gx_q, gy_d, gy_q : natural range 0 to 7 := 0;
  signal color_d, color_q, ink_d, ink_q : rgb_t := x"000";
  signal active_q : std_logic := '0';
  signal hundreds, tens, ones : natural range 0 to 9 := 0;
begin
  -- Decimal conversion is independent of pixel layout. The snapshot changes
  -- only in vertical blank, so these registers settle before visible video.
  process(clk)
  begin
    if rising_edge(clk) then
      hundreds <= game.attempts/100;
      tens <= (game.attempts/10) mod 10;
      ones <= game.attempts mod 10;
    end if;
  end process;
  -- One pixel of pipeline latency: layout/character selection, then font ROM.
  -- The top-level delays HSYNC/VSYNC by the same pixel before registering RGB.
  process(clk)
  begin
    if rising_edge(clk) then
      if pixel_ce = '1' then
        glyph_q <= glyph_d; gx_q <= gx_d; gy_q <= gy_d;
        color_q <= color_d; ink_q <= ink_d; active_q <= active;
      end if;
    end if;
  end process;
  rgb <= x"000" when active_q = '0' else
         ink_q when font_pixel(glyph_q,gx_q,gy_q) else color_q;
  process(all)
    variable color, ink : rgb_t;
    variable glyph : character;
    variable gx, gy : natural range 0 to 7;
    variable dx, dy : integer range -799 to 799;
    variable text_col : natural range 0 to 49;
    variable text_x : natural range 0 to 5;
    variable hud : string(1 to 48);
    variable footer : string(1 to 48);
    variable status : string(1 to 24);
  begin
    color := x"112"; ink := x"FFF"; glyph := ' '; gx := 0; gy := 0;
    -- Decode fixed 12-pixel text cells with comparisons, not signed division
    -- or modulo. This keeps the raster-to-RGB path within one 50 MHz cycle.
    text_col := 0; text_x := 0;
    for col in 0 to 49 loop
      if x >= 32+col*12 and x < 44+col*12 then
        text_col := col;
        text_x := (x-(32+col*12))/2;
      end if;
    end loop;
    -- Glyph row depends only on Y. Keep it out of the 16-card priority mux.
    for card_row in 0 to 3 loop
      for row in 0 to 6 loop
        if y >= 99+card_row*88+row*6 and y < 105+card_row*88+row*6 then gy := row; end if;
      end loop;
    end loop;
    if y >= 8 and y < 22 then gy := (y-8)/2;
    elsif y >= 40 and y < 54 then gy := (y-40)/2;
    elsif y >= 432 and y < 446 then gy := (y-432)/2;
    elsif y >= 458 and y < 472 then gy := (y-458)/2; end if;
    hud := (others => ' '); footer := (others => ' '); status := (others => ' ');
    hud(1 to 5) := "MODE ";
    if game.two_players = '1' then hud(6) := '2'; else hud(6) := '1'; end if;
    hud(10 to 12) := "P1:"; hud(13) := digit(game.score1);
    if game.two_players = '1' then
      hud(17 to 19) := "P2:"; hud(20) := digit(game.score2);
      hud(24 to 29) := "TURN P";
      if game.player = '0' then hud(30) := '1'; else hud(30) := '2'; end if;
    end if;
    hud(35 to 40) := "PAIRS:"; hud(41) := digit(game.pairs); hud(42 to 43) := "-8";
    footer(1 to 9) := "ATTEMPTS ";
    footer(10) := digit(hundreds);
    footer(11) := digit(tens);
    footer(12) := digit(ones);
    if game.state = READY then
      status(1 to 19) := "KEY1 START SW0 MODE";
    elsif game.state = SHUFFLE then status(1 to 9) := "SHUFFLING";
    elsif game.state = GAME_OVER then
      footer(18 to 35) := "KEY1 BACK TO TITLE";
      if game.two_players = '0' then status(1 to 8) := "COMPLETE";
      elsif game.score1 > game.score2 then status(1 to 7) := "P1 WINS";
      elsif game.score2 > game.score1 then status(1 to 7) := "P2 WINS";
      else status(1 to 4) := "DRAW"; end if;
    elsif game.state = PICK_FIRST then status(1 to 15) := "PICK FIRST CARD";
    elsif game.state = PICK_SECOND then status(1 to 16) := "PICK SECOND CARD";
    else status(1 to 12) := "CHECKING ..."; end if;

    -- Constant card rectangles avoid division by the 88-pixel grid pitch.
    for i in 0 to 15 loop
      dx := integer(x)-(144+(i mod 4)*88);
      dy := integer(y)-(80+(i/4)*88);
      if dx >= 0 and dx < 80 and dy >= 0 and dy < 80 then
        color := x"235";
        if face_up(game,i) then color := PALETTE(game.cards(i)); end if;
        if dx < 3 or dx >= 77 or dy < 3 or dy >= 77 then
          color := x"456";
          if game.matched(i) = '1' then color := x"4E9"; end if;
          if game.cursor = i and (game.state = PICK_FIRST or game.state = PICK_SECOND) then
            color := x"FF3";
          end if;
        end if;
        if dx >= 25 and dx < 55 and dy >= 19 and dy < 61 then
          for col in 0 to 4 loop
            if dx >= 25+col*6 and dx < 31+col*6 then gx := col; end if;
          end loop;
          glyph := '?';
          if face_up(game,i) then glyph := character'val(character'pos('A')+game.cards(i)); end if;
        end if;
      end if;
    end loop;
    if y >= 8 and y < 22 and x >= 32 and x < 32+TITLE'length*12 then
      glyph := TITLE(text_col+1); gx := text_x; ink := x"7DF";
    elsif y >= 8 and y < 22 and x >= 344 and x < 632 then
      glyph := status(text_col-26+1); gx := text_x; ink := x"FF7";
    elsif y >= 40 and y < 54 and x >= 32 and x < 608 then
      glyph := hud(text_col+1); gx := text_x;
    elsif y >= 432 and y < 446 and x >= 32 and x < 608 then
      glyph := footer(text_col+1); gx := text_x;
    elsif y >= 458 and y < 472 and x >= 32 and x < 32+CONTROLS'length*12 then
      glyph := CONTROLS(text_col+1); gx := text_x; ink := x"9AB";
    end if;
    glyph_d <= glyph; gx_d <= gx; gy_d <= gy;
    color_d <= color; ink_d <= ink;
  end process;
end;
