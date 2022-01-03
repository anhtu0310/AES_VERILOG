# AES encryptor project for VHDL design class
### ------current status: in progress--------
**Usage**
The verilog folder contains very fist designs of the AES-128 on Verilog HDL tested on Modelsim 10.5b
    - You can compile and run the **AES_tb** module for the AES testbench
    - The deign is not yet aligned with the architechture diagram, clock takes up to 103 clk for a cipher block, subyte LUT from key expansion and subyte module is not shared
The CPP program is for repesent AES design for later design a HDL model
