# Memory Match — DE10-Lite / VHDL

เกมจับคู่การ์ด 16 ใบ (4×4 / 8 คู่) สำหรับ **DE10-Lite, MAX 10 10M50DAF484C7G** เขียนด้วย VHDL-2008 ใช้ Quartus Prime Lite และ VGA 640×480 ที่ประมาณ **59.52 Hz**

![ภาพจากการจำลองวงจร VGA](docs/previews/playing.png)

> ภาพในเอกสารสร้างจาก VHDL renderer ใน simulation ไม่ใช่ภาพถ่ายจากบอร์ดจริง ผลตรวจสอบล่าสุดดูที่ [validation.md](docs/validation.md)

## เปิดและลงบอร์ด

1. เปิด `memory_match.qpf` ใน Quartus Prime Lite ซึ่งติดตั้ง MAX 10 device support แล้ว
2. เลือก **Processing → Start Compilation** หรือรัน `./scripts/build.ps1` ใน PowerShell
3. ต่อ USB-Blaster และจอ VGA เข้ากับ DE10-Lite
4. เปิด **Tools → Programmer** เลือก USB-Blaster และโหมด JTAG
5. เพิ่ม `output_files/memory_match.sof` เลือก **Program/Configure** แล้วกด **Start**
6. ตั้ง `SW9=0` เลือกโหมดด้วย `SW0` แล้วกด `KEY1` เพื่อเริ่ม

ไฟล์ `.sof` ใช้ทดลองผ่าน JTAG และไม่คงอยู่หลังปิดไฟ โปรเจกต์นี้ไม่เขียน configuration flash อัตโนมัติ

## วิธีเล่น

- `KEY0`: เลื่อนไปใบถัดไป เรียงจากซ้ายไปขวาและวนกลับจากใบที่ 16
- `KEY1`: เริ่มเกม / เปิดใบที่เลือก / กลับหน้าพร้อมเล่นเมื่อจบเกม
- `SW0=0`: คนเดียว เก็บครบ 8 คู่โดยใช้จำนวนครั้งให้น้อยที่สุด
- `SW0=1`: สองคน เริ่มผู้เล่น 1 จับคู่ถูกได้ 1 คะแนนและเล่นต่อ ผิดจึงสลับผู้เล่น
- `SW9=1`: รีเซ็ตเกม ค้างไว้เพื่อหยุดเกม ตั้งกลับเป็น 0 เพื่อพร้อมเล่น

เปิดใบที่สองแล้วทั้งคู่จะแสดง 1 วินาที ก่อนตรวจว่าตรงกันหรือไม่ การ์ด A–H มีอย่างละสองใบ คู่ที่ถูกเปิดค้าง กรอบเหลืองคือใบที่กำลังเลือก กรอบเขียวคือคู่ที่สำเร็จ

กดค้างไม่เลื่อนซ้ำ ปุ่มต้องคงที่ประมาณ 20 ms จึงรับการกด/ปล่อย หากเหตุการณ์สองปุ่มเกิดพร้อมกัน KEY1 มีลำดับก่อน เปลี่ยน SW0 ระหว่างเกมไม่มีผลจนเริ่มรอบใหม่ การเลือกใบเดิมหรือใบที่จับคู่แล้วไม่มีผล `ATTEMPTS` เพิ่มเมื่อเปิดใบที่สองสำเร็จและค้างที่ 999

## ไฟล์หลัก

- `rtl/`: package, input controller, game FSM, VGA timing, frame snapshot, renderer และ top-level
- `constraints/`: ขาบอร์ดและ clock 50 MHz; ตำแหน่งขาตรวจเทียบกับ DE10-Lite Golden Top ที่มากับ Quartus
- `sim/`: ชุดทดสอบแบบ assertion สำหรับเกม ปุ่ม VGA และวงจรรวม
- `scripts/`: คำสั่ง compile, simulation, รายงาน timing และสร้างภาพ PNG
- [เอกสารออกแบบ](docs/design.md): Block diagram, State diagram, State table และรายละเอียดวงจร
- [ผลตรวจสอบ](docs/validation.md): ผล compile/simulation และงานที่ต้องตรวจบนบอร์ด
- [รายการสาธิตบนบอร์ด](docs/hardware-checklist.md): ขั้นตอนเก็บภาพและผลทดลองจริง

## รัน simulation

ใช้ Questa Altera Starter FPGA Edition โดยให้ `vlib`, `vcom`, `vsim` อยู่ใน PATH และมี license ที่ใช้งานได้:

```powershell
./scripts/simulate.ps1
./scripts/export-previews.ps1
```

ผลอยู่ใน `build/sim/`: แต่ละ testbench มี `.log` และ `.wlf`; ภาพที่สร้างจาก renderer อยู่ใน `.ppm` และแปลงเป็น PNG ใน `docs/previews/` ได้ เปิด waveform เช่น:

```powershell
vsim -view build/sim/tb_game_core.wlf
```

รองรับ GHDL อีกทางผ่าน `./scripts/simulate.ps1 -Simulator ghdl` แต่เครื่องที่พัฒนาโปรเจกต์นี้บล็อก GHDL จึงตรวจด้วย Questa เท่านั้น

Testbench ลดค่า debounce และเวลารอเพื่อให้รันเร็ว โดยทดสอบจำนวนรอบ clock แบบตรงตัว ค่าบนบอร์ดใน `top` ยังคงเป็น 1,000,000 รอบ (20 ms) และ 50,000,000 รอบ (1 s)

## Compile ด้วย Quartus เวอร์ชันอื่น

```powershell
./scripts/build.ps1 -QuartusBin 'C:/path/to/quartus/bin64'
```

ดู `.fit.summary` สำหรับทรัพยากร และ `.sta.rpt` สำหรับ timing ใน `output_files/` การ compile สำเร็จอย่างเดียวไม่พอ ต้องตรวจว่าไม่มี `Timing requirements not met` ด้วย สามารถสร้างรายงานเส้นทาง timing เพิ่มด้วย `quartus_sta -t scripts/timing_report.tcl`

## ชุดส่งงาน

หลัง compile และทดสอบผ่าน รัน `./scripts/package.ps1` เพื่อสร้าง `build/memory_match_submission.zip` ซึ่งรวมซอร์ส โปรเจกต์ Quartus เอกสาร ภาพ simulation, waveform, test logs และไฟล์ `.sof` แล้ว ต้องแนบภาพหรือวิดีโอบอร์ดจริงเพิ่มเติมหลังสาธิต

## ขอบเขต

ไม่มีเสียง ไม่มีเวลาจำกัด ไม่มีอุปกรณ์ควบคุมภายนอก ไม่ใช้ framebuffer หรือ PLL สุ่มแบบกึ่งสุ่มจากจังหวะกดเริ่มเกม ไม่ใช่แหล่งสุ่มเชิงเข้ารหัสและไม่รับประกันว่าจะไม่ซ้ำรอบก่อน
