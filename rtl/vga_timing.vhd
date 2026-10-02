library ieee;
use ieee.std_logic_1164.all;

entity vga_timing is
  port (
    clk, reset : in std_logic;
    pixel_ce : out std_logic;
    x : out natural range 0 to 799;
    y : out natural range 0 to 524;
    active, hsync, vsync, frame_capture : out std_logic
  );
end;

architecture rtl of vga_timing is
  signal phase : std_logic := '0';
  signal h : natural range 0 to 799 := 0;
  signal v : natural range 0 to 524 := 0;
begin
  pixel_ce <= phase;
  x <= h;
  y <= v;
  active <= '1' when h < 640 and v < 480 else '0';
  hsync <= '0' when h >= 656 and h < 752 else '1';
  vsync <= '0' when v >= 490 and v < 492 else '1';
  -- One 50 MHz cycle at the boundary into vertical blank.
  frame_capture <= '1' when phase = '1' and h = 799 and v = 479 else '0';
  process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then phase <= '0'; h <= 0; v <= 0;
      else
        phase <= not phase;
        if phase = '1' then
          if h = 799 then
            h <= 0;
            if v = 524 then v <= 0; else v <= v+1; end if;
          else h <= h+1; end if;
        end if;
      end if;
    end if;
  end process;
end;
