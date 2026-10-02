library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;
use work.game_pkg.all;

entity tb_video is end;
architecture test of tb_video is
  signal clk : std_logic := '0';
  signal reset : std_logic := '1';
  signal ce, active, hs, vs, capture : std_logic;
  signal x : natural range 0 to 799;
  signal y : natural range 0 to 524;
  signal sx : natural range 0 to 799 := 0;
  signal sy : natural range 0 to 524 := 0;
  signal draw_active : std_logic := '1';
  signal live, saved, scene : view_t := INITIAL_VIEW;
  signal save : std_logic := '0';
  signal rgb : rgb_t;
begin
  clk <= not clk after 10 ns;
  timing : entity work.vga_timing port map(clk,reset,ce,x,y,active,hs,vs,capture);
  snapshot : entity work.frame_snapshot port map(clk,save,live,saved);
  drawing : entity work.renderer port map(clk,'1',sx,sy,draw_active,scene,rgb);
  process
    variable h_low, v_low, visible, captures : natural := 0;
    variable s : view_t;
    procedure tick is
    begin wait until rising_edge(clk); wait for 1 ns; end;
    procedure render_file(filename : string) is
      file output : text;
      variable line_out : line;
    begin
      file_open(output,filename,write_mode);
      write(line_out,string'("P3")); writeline(output,line_out);
      write(line_out,string'("640 480")); writeline(output,line_out);
      write(line_out,string'("255")); writeline(output,line_out);
      for row in 0 to 479 loop
        for col in 0 to 639 loop
          sx <= col; sy <= row; tick;
          for channel in 0 to 2 loop
            write(line_out,to_integer(unsigned(rgb(11-channel*4 downto 8-channel*4)))*17);
            write(line_out,' ');
          end loop;
        end loop;
        writeline(output,line_out);
      end loop;
      file_close(output);
    end;
  begin
    tick; tick; reset <= '0';
    for frame in 1 to 2 loop
      h_low := 0; v_low := 0; visible := 0; captures := 0;
      for row in 0 to 524 loop
        for col in 0 to 799 loop
          wait until rising_edge(clk) and ce = '1';
          assert x = col and y = row report "Raster count incorrect" severity failure;
          assert (active = '1') = (col < 640 and row < 480) report "Active area incorrect" severity failure;
          assert (hs = '0') = (col >= 656 and col < 752) report "HSYNC incorrect" severity failure;
          assert (vs = '0') = (row >= 490 and row < 492) report "VSYNC incorrect" severity failure;
          assert (capture = '1') = (col = 799 and row = 479) report "Snapshot boundary incorrect" severity failure;
          if active = '1' then visible := visible+1; end if;
          if hs = '0' then h_low := h_low+1; end if;
          if vs = '0' then v_low := v_low+1; end if;
          if capture = '1' then captures := captures+1; end if;
          wait for 1 ns;
          assert ce = '0' report "Pixel enable not divided by two" severity failure;
        end loop;
      end loop;
      assert visible = 307200 and h_low = 50400 and v_low = 1600 and captures = 1
        report "Frame totals incorrect" severity failure;
    end loop;
    s := INITIAL_VIEW; s.score1 := 3; live <= s; tick;
    assert saved = INITIAL_VIEW report "Snapshot changed outside capture" severity failure;
    save <= '1'; tick; save <= '0';
    assert saved = s report "Snapshot did not capture" severity failure;
    live <= INITIAL_VIEW; tick;
    assert saved = s report "Snapshot failed to hold" severity failure;
    draw_active <= '0'; sx <= 700; sy <= 500; tick;
    assert rgb = x"000" report "Blanking not black" severity failure;
    draw_active <= '1'; scene <= INITIAL_VIEW;
    render_file("ready.ppm");
    s := INITIAL_VIEW; s.state := PICK_FIRST; s.two_players := '1'; scene <= s;
    sx <= 144; sy <= 80; tick;
    assert rgb = x"FF3" report "Cursor border missing" severity failure;
    render_file("playing.ppm");
    s.state := REVEAL; s.first_card := 0; s.second_card := 8; s.attempts := 1; scene <= s;
    sx <= 154; sy <= 90; tick;
    assert rgb = x"B34" report "Revealed face color wrong" severity failure;
    render_file("reveal.ppm");
    s.state := GAME_OVER; s.matched := (others => '1'); s.pairs := 8;
    s.score1 := 4; s.score2 := 4; s.attempts := 15; scene <= s;
    render_file("draw.ppm");
    s.score1 := 5; s.score2 := 3; scene <= s; render_file("p1_wins.ppm");
    s.score1 := 3; s.score2 := 5; scene <= s; render_file("p2_wins.ppm");
    s.two_players := '0'; s.score1 := 8; s.score2 := 0; scene <= s; render_file("complete.ppm");
    report "PASS tb_video: two full VGA frames, sync, blanking, snapshot, renderer and seven PPM scenes";
    finish;
  end process;
  process begin wait for 100 ms; assert false report "Video test timeout" severity failure; end process;
end;
