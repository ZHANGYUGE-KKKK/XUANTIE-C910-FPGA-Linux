*******************************************************************************
** © Copyright 2019 Xilinx, Inc. All rights reserved.
** This file contains confidential and proprietary information of Xilinx, Inc. and 
** is protected under U.S. and international copyright and other intellectual property laws.
*******************************************************************************
**   ____  ____ 
**  /   /\/   / 
** /___/  \  /   Vendor: Xilinx 
** \   \   \/    
**  \   \        readme.txt
**  /   /        
** /___/   /\    
** \   \  /  \   Associated Filename: RDF0396
**  \___\/\___\ 
** 
**  Device: UltraScale+ Virtex FPGA
**  Purpose: System Controller for the VCU118 Evaluation Kit.
**  Reference: XTP447
**  
**   
*******************************************************************************
**
**  Disclaimer: 
**
**		This disclaimer is not a license and does not grant any rights to the materials 
**              distributed herewith. Except as otherwise provided in a valid license issued to you 
**              by Xilinx, and to the maximum extent permitted by applicable law: 
**              (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND WITH ALL FAULTS, 
**              AND XILINX HEREBY DISCLAIMS ALL WARRANTIES AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, 
**              INCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-INFRINGEMENT, OR 
**              FITNESS FOR ANY PARTICULAR PURPOSE; and (2) Xilinx shall not be liable (whether in contract 
**              or tort, including negligence, or under any other theory of liability) for any loss or damage 
**              of any kind or nature related to, arising under or in connection with these materials, 
**              including for any direct, or any indirect, special, incidental, or consequential loss 
**              or damage (including loss of data, profits, goodwill, or any type of loss or damage suffered 
**              as a result of any action brought by a third party) even if such damage or loss was 
**              reasonably foreseeable or Xilinx had been advised of the possibility of the same.


**  Critical Applications:
**
**		Xilinx products are not designed or intended to be fail-safe, or for use in any application 
**		requiring fail-safe performance, such as life-support or safety devices or systems, 
**		Class III medical devices, nuclear facilities, applications related to the deployment of airbags,
**		or any other applications that could lead to death, personal injury, or severe property or 
**		environmental damage (individually and collectively, "Critical Applications"). Customer assumes 
**		the sole risk and liability of any use of Xilinx products in Critical Applications, subject only 
**		to applicable laws and regulations governing limitations on product liability.

**  THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS PART OF THIS FILE AT ALL TIMES.

*******************************************************************************

** IMPORTANT NOTES **

The VCU118 System Controller is described in XTP447.

There are two versions of the VCU118 Firmware and the SCUI (System Controller User Interface).

Original SCUI:     v1.1
Original Firmware: v1.00
The ES1 VCU118 ships with v1.00 Firmware. 
You must use SCUI v1.1 with this Firmware.

Updated SCUI:     v2.30
Updated Firmware: v1.60
You must use SCUI v2.30 with this Firmware.

Do I need to update the Firmware?

In most cases, no. The main reason to update the Firmware is for VADJ setting issues.
The Original Firmware does not correctly set VADJ, if the FMC card EEPROM is unprogrammed.
You can still manually set the VADJ to the desired voltage with the Original SCUI.
The Updated Firmware fixes this problem and runs faster with the Updated SCUI. 
However, the Updated SCUI, version 2.30, CANNOT be used with the Original Firmware.
THe Board Interface Test (BIT, RDF0387) works equally well with both Firmware versions.

In RDF0396 both Firmware and SCUI versions are included, in respectively named folders:

C:\vcu118_scui
|   readme.txt
|
+---scui_v1.1
|       BOOT_v1.00.bin
|       config.json
|       log.txt
|       program_sysctrl.bat
|       program_sysctrl.tcl
|       SCUI.exe
|       verify_sysctrl.bat
|       verify_sysctrl.tcl
|
\---scui_v2.30
        BOOT_v1.60.bin
        config.json
        log.txt
        program_sysctrl.bat
        program_sysctrl.tcl
        SCUI.exe
        verify_sysctrl.bat
        verify_sysctrl.tcl

Use the program_sysctrl.bat in the respective folders to program the Firmware.
Use the verify_sysctrl.bat in the respective folders to verify the Firmware.

Manual programming instructions:
1)  Unzip RDF0396.
2)  Make sure a Xilinx Platform Cable is plugged into J82 with Flying Lead adapter.
    You will need to remove the PCIe chassis bracket to access J82.
      Flying-Leads to J82 pin mapping [6:1] = [Violet, White, Green, Yellow, Black, Red]
      Top to Bottom:
      Pin 6, SYSCTLR_TDO, Violet
      Pin 5, SYSCTLR_TDI, White
      Pin 4, SYSCTLR_TMS, Green
      Pin 3, SYSCTLR_TCK, Yellow
      Pin 2, GND, Black
      Pin 1, SYS_1V8, Red
3)  Install Jumper onto J110 header and cycle VCU118 power.
4)  Remove Jumper J110
5)  In Vivado, click "Open Hardware Manager"
6)  Click "Open target -> Auto Connect"
7)  On the right side rick click "xc7z010_1" and then click "Add Configuration Memory Device..."
8)  Scroll down in the bottom window of the popup dialog until you see "mt25qu128-qspi-x4-single".
9)  With "mt25qu128-qspi-x4-single" selected, click 'OK'
10) Click 'OK' on the next dialog indicating you want to program the device now.
11) Click the "..." next to the "Configuration file:" label and navigate to the desired BOOT_v1.xx.bin file.
12) Leave the "Zynq FSBL" field blank.
13) Click 'OK' and wait for the device to be programmed. Takes about 9 minutes to finish programming and verifying.
14) After programming finishes, cycle VCU118 power and close out of Vivado

If using the Updated Firmware: First time SCUI Setup

1)  Launch the v2.30 SCUI.exe.
2)  Make sure a USB cable is plugged from your computer to the VCU118 UART Micro USB port.
3)  Navigate to the "About" Tab
4)  Click the "Restore Board Defaults" button. This step takes about 3 minutes.

Device setup is now complete and the system controller can be used freely.
