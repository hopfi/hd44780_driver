----------------------------------------------------------------------------------
-- Name: Daniel Hopfinger
-- Date: 26.07.2021
-- Module: hd44780_driver_tb.vhd
-- Description: 
-- Testbench to hd44780_driver module.
--
-- History:
-- Version  | Date       | Information
-- ----------------------------------------
--  0.0.1   | 26.07.2021 | Initial version.
-- 
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library gen;

entity hd44780_driver_tb is
end hd44780_driver_tb;

architecture sim of hd44780_driver_tb is

    --! Timing constants that adjust speed of hd44780 control signal speed
    constant C_CLK_PERIOD      : time := 10 ns;
    constant C_CTRL_BUS_PERIOD : time := 2500 ns;
    constant C_CONV_TIME_FREQ  : integer := 1e9;

    constant C_SYS_CLK         : integer := (1 * C_CONV_TIME_FREQ) / (integer(time'POS(C_CLK_PERIOD)) / 1000);
    constant C_CTRL_BUS_SPEED  : integer := (1 * C_CONV_TIME_FREQ) / (integer(time'POS(C_CTRL_BUS_PERIOD)) / 1000);
    
    --! 30ns Differenze between actual en cycle time and calculated cycle time
    --! Delay is because of toggle delays in DUT and is aceptable
    constant C_TIME_DIFF_OFFSET : time := 30ns; 

    signal clk          : std_logic := '1';
    signal rst          : std_logic := '1';
    
    --! DUT signals
    signal start     : std_logic := '0';
    signal busy      : std_logic;
    signal disp_rw   : std_logic;
    signal disp_rs   : std_logic;
    signal disp_data : std_logic_vector(7 downto 0);
    signal en        : std_logic;
    signal rw        : std_logic;
    signal rs        : std_logic;
    signal data_out  : std_logic_vector(7 downto 0);
    signal data_in   : std_logic_vector(7 downto 0);
    signal data_tri  : std_logic;

    --! Array of data to be sent to display
    constant C_DISP_DATA_LENGTH : integer := 11;
    type data_arr is array (integer range 0 to C_DISP_DATA_LENGTH) of std_logic_vector(9 downto 0);
    signal display_data : data_arr :=
    ("00" & "00110000", --! Function set: 8bit Op, 5x8 Display
     "00" & "00001110", --! Display control: Display on, Cursor on
     "00" & "00000110", --! Entry mode: Increment address, shift cursor
     "10" & "01001000", --! Write DDRAM: H
     "10" & "01001001", --! Write DDRAM: I
     "10" & "01010100", --! Write DDRAM: T
     "10" & "01000001", --! Write DDRAM: A
     "10" & "01000011", --! Write DDRAM: C
     "10" & "01001000", --! Write DDRAM: H
     "10" & "01001001", --! Write DDRAM: I
     "00" & "00000111", --! Entry mode: Shift disply
     "10" & "00100000"  --! Write DDRAM: Space
     ); 

    signal data_input  : std_logic_vector(7 downto 0);
    signal data_output : std_logic_vector(7 downto 0);
    signal display_done : std_logic := '0';

begin

    clk <= not clk after C_CLK_PERIOD / 2;
    rst <= '0' after 10 * C_CLK_PERIOD;

    --! Process to provide stimulus for DUT
    --! 
    master_proc : process
    begin

        if rst = '1' then
            wait until rst = '0';
        end if;
        wait for 50 * C_CLK_PERIOD;
        wait until rising_edge(clk);

        wait until falling_edge(busy); --! Wait for display startup time to finish
        wait for 10 * C_CLK_PERIOD;

        --! Iterate through display_data array and start display operation
        for i in 0 to C_DISP_DATA_LENGTH - 1 loop

            disp_rw   <= display_data(i)(9);
            disp_rs   <= display_data(i)(8);
            disp_data <= display_data(i)(7 downto 0);
            start <= '1';
            wait for 1 * C_CLK_PERIOD;
            start <= '0';

            wait until falling_edge(busy);

        end loop;

        wait for 100 * C_CLK_PERIOD;

        std.env.stop(0);

    end process master_proc;

    --! DUT
    hd44780_drv : entity gen.hd44780_driver(rtl)
    generic map (
        G_SYSTEM_CLOCK => C_SYS_CLK,
        G_BAUD_RATE    => C_CTRL_BUS_SPEED
    )
    port map (
        i_sys_clk   => clk,
        i_sys_rst   => rst,
        i_start     => start,
        o_busy      => busy,
        i_disp_rw   => disp_rw,
        i_disp_rs   => disp_rs,
        i_disp_data => disp_data,
        o_en        => en,
        o_rw        => rw,
        o_rs        => rs,
        o_data      => data_out,
        i_data      => data_in,
        t_data      => data_tri
    );
    data_output <= data_out when data_tri = '0' else (others => 'Z');
    data_in     <= data_out when data_tri = '0' else data_input;

    --! Process to evaluate output of DUT
    slave_proc : process
    begin
        if rst = '1' then
            wait until rst = '0';
        end if;
        wait for 1 * C_CLK_PERIOD;
        wait until rising_edge(clk);

        wait until falling_edge(busy); --! Wait for display startup time to finish

        for i in 0 to C_DISP_DATA_LENGTH - 1 loop
            wait until rising_edge(start);
            wait until falling_edge(en);
            wait for 5 * C_CLK_PERIOD; --! Give enough time for busy signal to be set

            --! Check if busy signal of DUT is set
            assert busy = '1'
            report "Busy signal of DUT was not set!"
            severity failure;

            --! Check if data output is correct
            assert data_output = display_data(i)(7 downto 0)
            report "Display data output does not match expected value!" & lf &
                   "Expected: " & integer'image(to_integer(unsigned( display_data(i)(7 downto 0) ))) & lf &
                   "Actual: " & integer'image(to_integer(unsigned( data_output )))
            severity failure;

        end loop;

    end process slave_proc;

    --! Process to simulate delay of display
    timing_check_proc : process
        variable var_start_time : time;
        variable var_stop_time : time;
        variable var_time_diff : time;
    begin

        wait until falling_edge(busy); --! Wait for display startup time to finish

        loop 
            wait until rising_edge(en);
            var_start_time := now;
            wait until rising_edge(en);
            var_stop_time := now;
            var_time_diff := var_stop_time - var_start_time;

            --! Check correct time between en pulses given by C_CTRL_BUS_PERIOD
            assert var_time_diff - C_TIME_DIFF_OFFSET = C_CTRL_BUS_PERIOD
            report "Wrong period between en signals" & lf &
                "Expected: " & time'image(C_CTRL_BUS_PERIOD) & lf &
                "Actual: " & time'image(var_time_diff)
            severity failure;
        end loop;


    end process timing_check_proc;


    --! Process to simulate delay of display
    disp_delay_proc : process
    begin
        --! Initial display startup time
        data_input <= "10000000"; --! Set busy flag of display
        wait for 100 us; --! Arbitrary wait time of display (startup time of display)
        data_input <= "00000000"; --! Reset busy flag of display

        wait until falling_edge(busy); --! Wait for display startup time to finish

        loop 
            wait until rising_edge(start);
            wait until falling_edge(en);
            data_input <= "10000000"; --! Set busy flag of display
            wait for 37 us; --! Arbitrary wait time of display
            data_input <= "00000000"; --! Reset busy flag of display
        end loop;

    end process disp_delay_proc;


end sim;
