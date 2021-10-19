----------------------------------------------------------------------------------
-- Name: Daniel Hopfinger
-- Date: 16.07.2021
-- Module: hd44780_driver.vhd
-- Description:
-- Driver module to handle control of HD44780 LC Displays.
--
-- History:
-- Version  | Date       | Information
-- ----------------------------------------
--  0.0.1   | 16.07.2021 | Initial version.
--
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use ieee.numeric_std.all;


entity hd44780_driver is
    generic (
        G_SYSTEM_CLOCK   : integer range 5000000 to 400000000 := 100000000;    --! max: 400 Mhz, min: 5 Mhz
        G_BAUD_RATE      : integer range 100000 to 1000000 := 400000           --! max: 1 MHz, min: 100 kHz
    );
    port (
        i_sys_clk : in std_logic;                               --! system clock
        i_sys_rst : in std_logic;                               --! system reset

        --! User interface 
        i_start        : in  std_logic;                         --! Start transaction to display
        o_busy         : out std_logic;                         --! Busy state indicating when display is accesible
        i_disp_rw      : in  std_logic;                         --! Read/Write Select
        i_disp_rs      : in  std_logic;                         --! Register select
        i_disp_data    : in  std_logic_vector(7 downto 0);      --! Data to send to display

        --! HD44780 Interface
        o_en      : out std_logic;                              --! Enable signal 
        o_rw      : out std_logic;                              --! Read/Write select signal
        o_rs      : out std_logic;                              --! Register Select signal
        o_data    : out std_logic_vector(7 downto 0);           --! Data output signal
        i_data    : in  std_logic_vector(7 downto 0);           --! Data input signal
        t_data    : out std_logic_vector(7 downto 0)            --! Data tristate signal
    );
end hd44780_driver;

architecture rtl of hd44780_driver is

    constant C_BIT_PERIOD           : unsigned(15 downto 0) := to_unsigned((G_SYSTEM_CLOCK / G_BAUD_RATE), 16);
    constant C_ZERO_PERIOD          : unsigned(15 downto 0) := x"0003";
    constant C_ONE_QUARTER_PERIOD   : unsigned(15 downto 0) := "00" & C_BIT_PERIOD(15 downto 2);
    constant C_HALF_PERIOD          : unsigned(15 downto 0) := '0' & C_BIT_PERIOD(15 downto 1);
    constant C_THREE_QUARTER_PERIOD : unsigned(15 downto 0) := C_HALF_PERIOD + C_ONE_QUARTER_PERIOD;

    signal busy : std_logic;    --! internal signal of o_busy output port
    signal en   : std_logic;    --! internal signal of o_en output port
    signal rw   : std_logic;    --! internal signal of o_rw output port
    signal rs   : std_logic;    --! internal signal of o_rs output port

    signal data_in_r1 : std_logic_vector(7 downto 0);      --! Syncronizing registers
    signal data_in_r2 : std_logic_vector(7 downto 0);      --! Syncronizing registers
    signal data_in_r3 : std_logic_vector(7 downto 0);      --! Syncronizing registers
    signal data_in    : std_logic_vector(7 downto 0);      --! Internal signals for data port
    signal data_out   : std_logic_vector(7 downto 0);      --! Internal signals for data port
    signal data_tri   : std_logic_vector(7 downto 0);      --! Internal signals for data port
    signal disp_ready : std_logic; --! Buffer signal for busy flag of lcd display

    signal cnt        : unsigned(15 downto 0);          --! Counter signal to generate enable cycle
    signal cnt_en     : std_logic;                      --! Counter signal to generate enable cycle
    signal cnt_start  : std_logic;                      --! Counter signal to generate enable cycle
    signal cnt_zero_pulse  : std_logic;                 --! Pulse signals for each part of a period
    signal cnt_one_pulse   : std_logic;                 --! Pulse signals for each part of a period
    signal cnt_two_pulse   : std_logic;                 --! Pulse signals for each part of a period
    signal cnt_three_pulse : std_logic;                 --! Pulse signals for each part of a period
    signal cnt_four_pulse  : std_logic;                 --! Pulse signals for each part of a period

    type drv_fsm is (
        init, 
        idle,
        get_busy_flag,
        set_data
    );
    signal drv_state : drv_fsm;

begin

    --! internal signals mapped to output ports
    o_busy  <= busy;
    o_en    <= en;
    o_rw    <= rw;
    o_rs    <= rs;

    --! Insert following line to top module level to infer tristate buffer
    --io_data <= data_out when data_tri = '0' else x"ZZ";
    data_in <= i_data;
    o_data  <= data_out;
    t_data  <= data_tri;



    --! Synchronisation of data lines
    sync_proc : process (i_sys_clk)
    begin
        if rising_edge(i_sys_clk) then
            if i_sys_rst = '1' then
                data_in_r1 <= (others => '0');
                data_in_r2 <= (others => '0');
                data_in_r3 <= (others => '0');
            else
                data_in_r1 <= data_in;
                data_in_r2 <= data_in_r1;
                data_in_r3 <= data_in_r2;
            end if;
        end if;
    end process;

    --! State machine to send data to display
    i2c_proc : process (i_sys_clk)
    begin
        if rising_edge(i_sys_clk) then
            if i_sys_rst = '1' then
                drv_state <= init;
            else
                cnt_start <= '0';

                case drv_state is
                    when init =>
                        busy       <= '1';
                        en         <= '0';
                        data_tri   <= x"FF";
                        disp_ready <= '0';
                        cnt_start  <= '1';

                        drv_state <= get_busy_flag;

                    when idle =>
                        if i_start = '1' then
                            busy       <= '1';
                            cnt_start  <= '1';
                            disp_ready <= '0';
                            drv_state  <= set_data;
                        end if;

                    when set_data =>
                        rw       <= i_disp_rw;
                        rs       <= i_disp_rs;
                        data_tri <= x"00";
                        data_out <= i_disp_data;

                        if cnt_zero_pulse = '1' then
                            en <= '1';
                        end if;

                        if cnt_two_pulse = '1' then
                            en <= '0';
                        end if;

                        if cnt_four_pulse = '1' then
                            cnt_start <= '1';
                            drv_state <= get_busy_flag;
                        end if;
                    
                    when get_busy_flag =>
                        rw       <= '1';
                        rs       <= '0';
                        data_tri <= x"FF";
                        
                        if cnt_zero_pulse = '1' then
                            en <= '1';
                        end if;
                        
                        if cnt_two_pulse = '1' then
                            if data_in_r3(7) = '0' then
                                disp_ready <= '1';
                            end if;
                            en <= '0';
                        end if;

                        if cnt_four_pulse = '1' then
                            if disp_ready = '1' then
                                busy <= '0';
                                drv_state <= idle;
                            else
                                cnt_start <= '1';
                            end if;
                        end if;
                
                    when others =>
                        null;
                end case;

            end if;
        end if;
    end process i2c_proc;

    --! Counter process
    cnt_proc : process (i_sys_clk)
    begin
        if rising_edge(i_sys_clk) then
            if i_sys_rst = '1' then
                cnt_en <= '0';
                cnt <= (others => '0');
                cnt_zero_pulse  <= '0';
                cnt_one_pulse   <= '0';
                cnt_two_pulse   <= '0';
                cnt_three_pulse <= '0';
                cnt_four_pulse  <= '0';
            else
                cnt_zero_pulse  <= '0';
                cnt_one_pulse   <= '0';
                cnt_two_pulse   <= '0';
                cnt_three_pulse <= '0';
                cnt_four_pulse  <= '0';


                if cnt_start = '1' then
                    cnt <= (others => '0');
                    cnt_en <= '1';
                end if;

                if cnt_en = '1' then
                    cnt <= cnt + 1;

                    if cnt = C_ZERO_PERIOD then
                        cnt_zero_pulse <= '1';
                    end if;

                    if cnt = C_ONE_QUARTER_PERIOD then
                        cnt_one_pulse <= '1';
                    end if;

                    if cnt = C_HALF_PERIOD then
                        cnt_two_pulse <= '1';
                    end if;

                    if cnt = C_BIT_PERIOD then
                        cnt_four_pulse <= '1';
                        cnt_en <= '0';
                    end if;
                end if;

            end if;
        end if;
    end process cnt_proc;


end rtl;