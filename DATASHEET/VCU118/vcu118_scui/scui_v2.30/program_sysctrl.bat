@ECHO OFF
echo Power off VCU118
echo Attach Xilinx Platform Cable to J82 with Flying Lead adapter
echo Flying-Leads to J82 pin mapping [6:1] = 
echo[Violet, White, Green, Yellow, Black, Red]
echo Top to Bottom:
echo  Pin 6, SYSCTLR_TDO, Violet
echo  Pin 5, SYSCTLR_TDI, White
echo  Pin 4, SYSCTLR_TMS, Green
echo  Pin 3, SYSCTLR_TCK, Yellow
echo  Pin 2, GND,         Black
echo  Pin 1, SYS_1V8,     Red
pause
echo Put jumper on J110
echo Power on VCU118.
echo Remove jumper on J110.
pause
@ECHO ON
call C:\\Xilinx\\Vivado\\2019.1\\.\\bin\\vivado.bat -mode batch -source program_sysctrl.tcl
if exist *isWriteableTest*.tmp del /F *isWriteableTest*.tmp
if exist vivado_*.backup.jou del /F vivado_*.backup.jou
if exist vivado_*.backup.log del /F vivado_*.backup.log
if exist vivado_*.str del /F vivado_*.str
pause
